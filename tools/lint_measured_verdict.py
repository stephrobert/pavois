#!/usr/bin/env python3
"""FAIL if a check filters its command down to the very thing its matcher then asserts.

WHY (#359)

`kconfig-gcc-plugin-structleak` ran, for two years, this:

    describe command("grep -hE '^(CONFIG_GCC_PLUGIN_STRUCTLEAK|CONFIG_INIT_STACK_ALL_ZERO)=y' ...")
      its('stdout') { should match(/=y$/) }

The command keeps only the lines that end in `=y`, and the matcher then demands a line ending in
`=y`. The check can produce exactly two outcomes: the filter found something, or stdout is empty.
It cannot tell "the option is off" from "the kernel config could not be read", because both come
back as nothing at all. The FAIL it reports in the second case was never measured.

That is not a theoretical concern. The first campaign to run outside Debian failed on five of five
platforms, and four controls of this shape were the whole reason.

THE RULE: a command may filter, and a matcher may assert, but the matcher must not assert what the
filter already guaranteed. Either widen the command so the failing state also produces a line
(`^(# )?CONFIG_X[= ]` keeps `# CONFIG_X is not set`), or make absence speak with the repository's
own sentinel idiom (`|| echo PAVOIS_NO_KERNEL_CONFIG`, then `should_not match(/PAVOIS_.../)`).

WHAT IT CANNOT DO, AND WHY THAT IS NOT A GAP

The property that actually matters is "when this check fails, does it produce any output?", and
reading a corpus cannot answer it in general. An attempt to widen this linter towards it flagged
498 checks, including `auditctl -l | grep perm_mod` asserting `/(-k +|key=)perm_mod\\b/`, where the
matcher demands MORE than the filter guarantees and nothing is circular at all. A guard that loud
is a guard nobody reads.

So this stays narrow and `tools/validate_run.py` remains the authority: it runs on a real machine
and sees the empty stdout itself. What is added here is the two things a runtime check cannot give,
because they never run: a shape refused before it reaches a VM, and `template_guard()`, which
covers the one place the shape is generated 59 times over.

An earlier version of this file argued that `should match(/\\S/)` on a filtering command was fine,
since "empty stdout IS the stated failure and a reader can see that". The campaigns disagreed:
`ssh-use-directory-configuration` and `sysctl-kernel-unprivileged_bpf_disabled` both reported
`expected "" to match /\\S/`, which is a verdict on nothing however legible the source is. Both now
carry a sentinel. The exemption stays for the shape, the two controls no longer need it.

Starts at zero and stays there: there is no migration list, because at the time of writing the
corpus has no occurrence left.

    mise run lint:measured-verdict
    python3 tools/lint_measured_verdict.py --selftest
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "docs" / "reference" / "rules.yml"
# Templates are expanded here, one file per OS. Generated (gitignored), so `mise run gen` first.
GENERATED = ROOT / "docs" / "reference" / "pavois-content"

# What the command keeps: the pattern of a grep in the pipeline.
GREP_PATTERN = re.compile(r"grep\s+(?:-\w+\s+)*['\"]([^'\"]+)['\"]")
# What the matcher demands.
MATCHER = re.compile(r"should\s+match\(/(.+?)/[a-z]*\)")

# A matcher that means "the output is not empty" states its own failure mode, whatever the command
# filtered. Not circular, and legible as written.
PRESENCE_ONLY = {r"\S", r"\S+", r".", r".+"}

# A sentinel alternative is the repository's way of making absence speak; it is never the thing a
# matcher is circular about.
_SENTINEL = re.compile(r"^\(?PAVOIS_[A-Z_]+\)?$")
# An alternative carrying regex syntax is not a literal the filter guarantees.
_METACHAR = re.compile(r"[\[\]()?*+{}\\]")


def _alternatives(pattern: str) -> list[str]:
    """The branches of a grep alternation, each stripped of the anchors and parens around it.

    `^(CONFIG_X=|PAVOIS_NO_KERNEL_CONFIG)` becomes ["CONFIG_X=", "PAVOIS_NO_KERNEL_CONFIG"], so one
    branch being circular is visible even when another branch is a sentinel.
    """
    return [strip_anchors(a).strip("()") for a in pattern.split("|")]


def strip_anchors(rx: str) -> str:
    """The comparable core of a regex: anchors and trailing quantifiers carry no value here."""
    return rx.strip().lstrip("^").rstrip("$").strip()


def circular(lines: list[str]) -> list[str]:
    """Every (command pattern, matcher) pair where the matcher asserts
    what the filter already guaranteed."""
    text = "\n".join(lines)
    if "command(" not in text:
        return []

    patterns = GREP_PATTERN.findall(text)
    if not patterns:
        return []

    problems = []
    for raw in MATCHER.findall(text):
        core = strip_anchors(raw)
        if core in PRESENCE_ONLY or not core:
            continue
        for pat in patterns:
            # The matcher is circular when the filter already guarantees what it asks for, in
            # either direction: `grep '=y'` + `match(/=y$/)`, and `grep '^CONFIG_X='` +
            # `match(/^CONFIG_X=y$/)`.
            if core in pat or strip_anchors(pat) in core:
                problems.append(f"command keeps /{pat}/, matcher then demands /{raw}/")
                break
            # ... and it stays circular when a sentinel is bolted on beside it. The kconfig
            # template carried `grep -E '^(CONFIG_X=|PAVOIS_NO_KERNEL_CONFIG)'` for two years: the
            # sentinel answers "there was no config to read", which is a DIFFERENT question from
            # "the option is off". An early return on `PAVOIS_` anywhere in the text waved all 59
            # rendered controls through, so the alternatives are judged one by one.
            #
            # Only for a pattern that CARRIES a sentinel, though. Judging every alternation this way
            # flagged 498 checks, among them `auditctl -l | grep perm_mod` asserting
            # `/(-k +|key=)perm_mod\b/`: there the matcher demands MORE than the filter guarantees,
            # which is not circular. Narrow beats loud, or nobody reads the output.
            alts = _alternatives(pat)
            if any(_SENTINEL.match(a) for a in alts) and any(
                a and not _SENTINEL.match(a) and not _METACHAR.search(a) and a in core for a in alts
            ):
                problems.append(f"command keeps /{pat}/, matcher then demands /{raw}/")
                break
    return problems


def variants(check):
    """A check is a list of lines, or an @os map of such lists."""
    if isinstance(check, dict) and "@os" in check:
        yield from check["@os"].items()
    elif isinstance(check, list):
        yield "*", check


def scan(rules: dict) -> list[str]:
    hits = []
    for cid, body in sorted(rules.items()):
        if not isinstance(body, dict) or "check" not in body:
            continue
        seen = set()
        for os_name, lines in variants(body["check"]):
            if not isinstance(lines, list):
                continue
            for problem in circular(lines):
                if problem in seen:
                    continue  # one control, one message, not nine @os copies of it
                seen.add(problem)
                hits.append(f"{cid} [{os_name}]: {problem}")
    return hits


def template_guard() -> list[str]:
    """The kconfig template must keep the DISABLED form of an option, not just the enabled one.

    This is asserted directly rather than inferred from rendered output. `grep '^CONFIG_X='` drops
    `# CONFIG_X is not set`, so a `set: true` control failed on an empty stdout: 59 rendered
    controls, and on one Ubuntu 26.04 campaign it cost a whole grade (a HIGH weighs 15 points, and
    kconfig-page-table-isolation reported `expected "" to match` on a machine nobody had measured).

    Kept deliberately small. A general "can this check produce an empty stdout when it fails?" is
    not decidable by reading the corpus, which is what `tools/validate_run.py` is for, at runtime,
    on a real machine. This guard covers the one place the shape is generated 59 times over.
    """
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        import templates  # noqa: PLC0415  the module under guard
    except ImportError:
        return ["tools/templates.py could not be imported, so the kconfig template was NOT checked"]

    rendered = templates._kconfig_exp({"option": "CONFIG_PROBE", "value": "y", "set": True})
    cmd = rendered[0]
    if "(# )?CONFIG_PROBE[= ]" not in cmd:
        return [
            "the kconfig template filters to the ENABLED form only: a disabled option produces "
            "no output, so the FAIL it reports was never measured. Keep `(# )?<opt>[= ]`."
        ]
    return []


def selftest() -> int:
    """The exact shapes, before and after #359, plus the two that must NOT be flagged."""
    cases = [
        (
            "circular: filter =y, assert =y",
            [
                "describe command(\"grep -hE '^(CONFIG_A|CONFIG_B)=y' /boot/config\") do",
                "  its('stdout') { should match(/=y$/) }",
                "end",
            ],
            True,
        ),
        (
            "circular: filter ^CONFIG_X=, assert ^CONFIG_X=y$",
            [
                "describe command(\"grep -h '^CONFIG_REFCOUNT_FULL=' /boot/config\") do",
                "  its('stdout') { should match(/^CONFIG_REFCOUNT_FULL=y$/) }",
                "end",
            ],
            True,
        ),
        (
            "fixed: the filter keeps the disabled form too, so a FAIL carries its line",
            [
                "describe command(\"cat /boot/config | grep -E '^(# )?(CONFIG_A|CONFIG_B)[= ]'"
                ' || echo PAVOIS_NO_KERNEL_CONFIG") do',
                "  its('stdout') { should_not match(/PAVOIS_NO_KERNEL_CONFIG/) }",
                "  its('stdout') { should match(/^(CONFIG_A|CONFIG_B)=y$/) }",
                "end",
            ],
            False,
        ),
        (
            "witness: presence assertion states its own failure",
            [
                "describe command('grep -iE \"^Include /etc/ssh\" /etc/ssh/sshd_config') do",
                "  its('stdout') { should match(/\\S/) }",
                "end",
            ],
            False,
        ),
        (
            "witness: a dump, not a filter",
            [
                "describe command('sshd -T') do",
                "  its('stdout') { should match(/^permitrootlogin no$/) }",
                "end",
            ],
            False,
        ),
        (
            "witness: not a command at all",
            ["describe file('/etc/passwd') do", "  it { should exist }", "end"],
            False,
        ),
        # The kconfig template as it stood for two years. Its sentinel answers "there was no config
        # to read"; nothing answered "the config was read and the option is off", so a disabled
        # option failed on an empty stdout. 59 rendered controls, and an early return on `PAVOIS_`
        # in the text used to wave every one of them through.
        (
            "circular even with a sentinel beside it (the old kconfig template)",
            [
                "describe command(\"cat /c | grep -E '^(CONFIG_X=|PAVOIS_NONE)'\") do",
                "  its('stdout') { should_not match(/PAVOIS_NONE/) }",
                "  its('stdout') { should match(/^CONFIG_X=y$/) }",
                "end",
            ],
            True,
        ),
        (
            "the same template, widened to keep the disabled form",
            [
                "describe command(\"cat /c | grep -E '^((# )?CONFIG_X[= ]|PAVOIS_NONE)'\") do",
                "  its('stdout') { should_not match(/PAVOIS_NONE/) }",
                "  its('stdout') { should match(/^CONFIG_X=y$/) }",
                "end",
            ],
            False,
        ),
        (
            "witness: every branch of the command echoes, so stdout is never empty",
            [
                "describe command('sh -c \"grep -i x /etc/f; echo ok-b\"') do",
                "  its('stdout') { should match(/^ok /) }",
                "end",
            ],
            False,
        ),
    ]
    bad = 0
    for label, lines, want in cases:
        got = bool(circular(lines))
        if got != want:
            print(f"  FAIL [{label}]: expected {want}, got {got}", file=sys.stderr)
            bad += 1
    print(f"lint:measured-verdict selftest: {len(cases) - bad}/{len(cases)} cases")
    return 1 if bad else 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()

    path = Path(sys.argv[1]) if len(sys.argv) > 1 else RULES
    hits = scan(yaml.safe_load(path.read_text()))
    hits += template_guard()
    checked = path.name + " + the kconfig template"
    if hits:
        print(
            f"lint:measured-verdict: {len(hits)} check(s) assert what they already filtered",
            file=sys.stderr,
        )
        for h in hits:
            print("  " + h, file=sys.stderr)
        print(
            "\n  Such a check cannot tell a real deviation from a command that produced nothing.\n"
            "  Widen the filter so the failing state emits a line, or make absence\n"
            "  speak with a PAVOIS_* sentinel and a should_not matcher.",
            "  a PAVOIS_* sentinel and a should_not matcher.",
            file=sys.stderr,
        )
        return 1

    print(f"lint:measured-verdict: clean ({checked})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
