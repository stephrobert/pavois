#!/usr/bin/env python3
"""The applicability vocabulary: one closed set, one message grammar, one emitter.

WHY THIS EXISTS (#324)

"Does this requirement apply to this host?" used to be answered by four unrelated mechanisms, each
invented the day somebody hit a case: a hand-written `only_if` inside a check (27 occurrences, in
two wordings), a guard baked into a template (190 rendered occurrences on debian12 alone), a
`waiver:`, and `remediation_class`. A host with no separate /home was therefore reported non
compliant 24 times for one fact, because the fact lived on the prerequisite control and the 24
dependants could not see it.

The norms state applicability themselves: CIS words its mount audits "IF a separate partition
exists for <mp>", its cron rules "IF cron is installed". So applicability becomes a DECLARED field
of the rule base, `applies_if:`, rendered from here and checked from here.

THE RULE THAT GOVERNS IT, and it is the one that keeps this from becoming a way to make failures
disappear: "one fact counted N times" is NOT a justification. Otherwise every dependency chain
collapses the score, and auditd being absent would make 60 audit rules not applicable, while CIS
writes no "if auditd is installed" anywhere: those must FAIL. The source of a non-applicability is
the NORM'S OWN WORDING or a physical fact, never "my prerequisite is missing". That is what
`because:` records, and a condition without one is refused.

NO ESCAPE HATCH. There is deliberately no `shell:` key. An escape hatch "counted as debt" is a
band-aid with a counter on it, and a closed vocabulary that admits a door is not closed: the
message grammar and the sibling lint both lose their guarantee at the first free-form command,
whose `n/a: requires shell: grep -q ...` no auditor can read. The first case that fits no key is a
pull request that adds the key: one row here, its message, its lint rule, its render test.

Usage: python3 tools/applies_if.py --selftest
"""

from __future__ import annotations

import re
import sys


# A Ruby string literal, single-quoted, the way render_reference writes them.
def _rb(s) -> str:
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'") + "'"


def _package(v):
    return f"package({_rb(v)}).installed?", f"package {v} installed"


def _path(v):
    return f"file({_rb(v)}).exist?", f"{v} to exist"


def _mount(v):
    return f"mount({_rb(v)}).mounted?", f"{v} mounted"


def _unit(v):
    return f"service({_rb(v)}).installed?", f"unit {v} installed"


def _command(v):
    return f"command({_rb(v)}).exist?", f"command {v} available"


def _glob(v):
    probe = f"ls -d {v} >/dev/null 2>&1"
    return f"command({_rb(probe)}).exit_status == 0", f"a path matching {v}"


def _file_match(v):
    if not isinstance(v, dict) or "path" not in v or "pattern" not in v:
        raise ValueError("file_match takes {path, pattern}")
    return (
        f"file({_rb(v['path'])}).content.to_s.match?(/{v['pattern']}/)",
        f"{v['pattern']} in {v['path']}",
    )


def _arch(v):
    vals = v if isinstance(v, list) else [v]
    alt = "|".join(re.escape(str(a)) for a in vals)
    return f"os.arch.to_s.match?(/\\A({alt})/)", f"arch {'|'.join(str(a) for a in vals)}"


_KERNEL_RE = re.compile(r"^(<=|>=|<|>)\s*(\d+(?:\.\d+)*)$")


def _kernel(v):
    m = _KERNEL_RE.match(str(v).strip())
    if not m:
        raise ValueError("kernel takes a comparison such as '>= 5.5'")
    op, ver = m.group(1), m.group(2)
    running = "Gem::Version.new(command('uname -r').stdout[/\\d+(\\.\\d+)+/].to_s)"
    return f"{running} {op} Gem::Version.new({_rb(ver)})", f"kernel {op} {ver}"


def _virt(v):
    if v is not False:
        raise ValueError("virt takes only false (bare metal only)")
    return "command('systemd-detect-virt -q').exit_status != 0", "bare metal"


# The closed set. A key that is not here is refused, by the renderer and by the linter alike.
VOCABULARY = {
    "package": _package,
    "path": _path,
    "mount": _mount,
    "unit": _unit,
    "command": _command,
    "glob": _glob,
    "file_match": _file_match,
    "arch": _arch,
    "kernel": _kernel,
    "virt": _virt,
}

COMBINERS = ("not", "any")


def _one(cond: dict) -> tuple[str, str]:
    """(ruby expression, human phrase) for a single condition, combiners included."""
    keys = [k for k in cond if k != "because"]
    if len(keys) != 1:
        raise ValueError(f"a condition holds exactly one predicate, got {keys}")
    key = keys[0]
    val = cond[key]
    if key == "not":
        expr, phrase = _one(val if isinstance(val, dict) else {})
        return f"!({expr})", f"no {phrase}"
    if key == "any":
        if not isinstance(val, list) or len(val) < 2:
            raise ValueError("any takes a list of at least two conditions")
        parts = [_one(c) for c in val]
        return (
            "(" + " || ".join(e for e, _ in parts) + ")",
            "any of: " + ", ".join(p for _, p in parts),
        )
    if key not in VOCABULARY:
        raise ValueError(f"unknown predicate {key!r}: the vocabulary is {sorted(VOCABULARY)}")
    return VOCABULARY[key](val)


def lines(conds) -> list[str]:
    """One `only_if` per condition.

    Per condition rather than one conjunction, on purpose: InSpec reports the message of the first
    guard that is false, so the operator reads exactly which object is missing rather than a
    sentence listing five.
    """
    out = []
    for cond in conds or []:
        expr, phrase = _one(cond)
        out.append(f"  only_if({_rb('n/a: requires ' + phrase)}) {{ {expr} }}")
    return out


def problems(cid: str, conds) -> list[str]:
    """What is wrong with this control's applies_if, said the way a linter says it."""
    bad = []
    if conds is None:
        return bad
    if not isinstance(conds, list) or not conds:
        return [f"{cid}: applies_if must be a non-empty list of conditions"]
    for cond in conds:
        if not isinstance(cond, dict):
            bad.append(f"{cid}: a condition must be a mapping, got {type(cond).__name__}")
            continue
        # `because` is mandatory and it is the whole point: it records WHERE the norm says this
        # requirement is conditional. Without it, applicability is an opinion.
        if not str(cond.get("because", "")).strip():
            bad.append(f"{cid}: a condition with no `because`: name the norm wording or the fact")
        try:
            _one(cond)
        except ValueError as e:
            bad.append(f"{cid}: {e}")
    return bad


# ---- falsification -------------------------------------------------------------------------

_CASES = [
    (
        [{"mount": "/home", "because": "CIS 1.1.2.x"}],
        "only_if('n/a: requires /home mounted') { mount('/home').mounted? }",
    ),
    (
        [{"package": "cron", "because": "CIS 2.4.1.1"}],
        "only_if('n/a: requires package cron installed') { package('cron').installed? }",
    ),
    (
        [{"path": "/etc/motd", "because": "CIS 1.7.1"}],
        "only_if('n/a: requires /etc/motd to exist') { file('/etc/motd').exist? }",
    ),
    (
        [{"arch": ["aarch64", "arm"], "because": "arm only"}],
        "only_if('n/a: requires arch aarch64|arm') { os.arch.to_s.match?(/\\A(aarch64|arm)/) }",
    ),
    (
        [{"virt": False, "because": "bare metal"}],
        "only_if('n/a: requires bare metal') "
        "{ command('systemd-detect-virt -q').exit_status != 0 }",
    ),
    (
        [{"not": {"package": "rsyslog"}, "because": "other logger"}],
        "only_if('n/a: requires no package rsyslog installed') "
        "{ !(package('rsyslog').installed?) }",
    ),
]

_REFUSED = [
    ([{"mount": "/home"}], "no `because`"),
    ([{"shell": "grep -q x /etc/f", "because": "because"}], "unknown predicate"),
    ([{"kernel": "5.5", "because": "because"}], "malformed kernel"),
    ([{"virt": True, "because": "because"}], "virt true"),
    ([{"mount": "/a", "path": "/b", "because": "because"}], "two predicates in one condition"),
    ([{"any": [{"path": "/a", "because": "b"}], "because": "b"}], "any with one branch"),
]


def selftest() -> int:
    ok = True
    print("the emitter renders:")
    for conds, want in _CASES:
        got = lines(conds)[0].strip()
        if got == want:
            print(f"  ok   {list(conds[0])[0]}")
        else:
            print(f"  FAIL {list(conds[0])[0]}\n       got  {got}\n       want {want}")
            ok = False

    print("\nand refuses:")
    for conds, label in _REFUSED:
        if problems("zz-test", conds):
            print(f"  ok   {label}")
        else:
            print(f"  FAIL {label}: accepted, and it must not be")
            ok = False

    # A vocabulary is only closed if something proves the door is shut.
    if "shell" in VOCABULARY:
        print("\n  FAIL a `shell` key is back in the vocabulary: see the docstring")
        ok = False
    else:
        print("\n  ok   no shell escape hatch")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv[1:] else selftest())
