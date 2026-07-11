#!/usr/bin/env python3
"""Coherence linter for docs/reference/rules.yml — the guardrail that would have caught the
defects the SSG bootstrap left behind, without needing a VM.

Every finding below was a REAL bug found by scanning a live host, which means it survived
`validate:mappings` and `gen:verify`: those only prove the pipeline is consistent, not that a
control is *coherent*. This lints the content itself:

  ssg-leak        the check asserts on an SSG *remediation sentence* instead of the system
                  (ssh-use-directory-configuration matched "remediation probably already happened")
  bad-param       a check template carries an SSG variable placeholder instead of a real value
                  (cmdline-nousb had param `kernel=ALL` instead of `nousb`: never passes)
  guard-asymmetry the same control id is guarded by only_if on one OS and unguarded on another
                  (service-sssd-enabled was guarded on debian, unguarded on rhel -> permanent FAIL
                  on a host that does not even use SSSD)
  rem-asymmetry   the control is remediable on one OS and has NO remediation on another
                  (123 of rhel10's controls had none, vs 3 on debian12)
  path-mismatch   a `file` remediation touches a path the check never mentions
                  (fileperm-unauthorized-world-writable "remediated" by chmod 0775 /tmp)

Usage: tools/lint_rules.py [--strict]   (--strict: exit 1 on any finding)
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import templates  # noqa: E402  (a control's check may be a template: expand it before linting)

RULES = ROOT / "docs" / "reference" / "rules.yml"

# phrases that betray SSG remediation prose pasted into a check
STICKY = {"/tmp", "/var/tmp", "/dev/shm"}  # nosec B108 - these are audit targets, not temp files

# The check text is Ruby with escaped literals (\s+, \ ), so match on the words, not on spacing.
SSG_PROSE = re.compile(
    r"remediation.{0,12}probably|not.{0,3}doing.{0,3}anything|already.{0,3}exists,|please.{0,3}review",
    re.I,
)


def per_os(entry, field):
    """{os: value} for a field, whether it is shared or @os-keyed."""
    v = entry.get(field)
    oses = entry.get("applicable_os") or []
    if isinstance(v, dict) and "@os" in v:
        return {os: v["@os"].get(os) for os in oses}
    return dict.fromkeys(oses, v)


def main():
    d = yaml.safe_load(RULES.read_text(encoding="utf-8"))
    findings = defaultdict(list)

    for cid, e in sorted(d.items()):
        if not isinstance(e, dict) or "applicable_os" not in e:
            continue
        checks = per_os(e, "check")
        rems = per_os(e, "remediation")
        for os, tpl in per_os(e, "template").items():  # a templated check is still a check
            if isinstance(tpl, dict) and not checks.get(os):
                checks[os] = templates.expand(tpl)

        for os, lines in checks.items():
            text = " ".join(lines or [])
            if SSG_PROSE.search(text):
                findings["ssg-leak"].append(f"{cid} [{os}]: check asserts on SSG prose")

        for os, tpl in per_os(e, "template").items():
            if not isinstance(tpl, dict):
                continue
            p = str(tpl.get("param", ""))
            # boot parameters are lowercase: an upper-case token is an unexpanded SSG variable
            if tpl.get("name") == "cmdline" and re.search(r"[A-Z]{2,}", p):
                findings["bad-param"].append(
                    f"{cid} [{os}]: cmdline param {p!r} is not a boot param"
                )

        guarded = {os: ("only_if" in " ".join(ln or [])) for os, ln in checks.items() if ln}
        if len(set(guarded.values())) > 1:
            on = sorted(o for o, g in guarded.items() if g)
            off = sorted(o for o, g in guarded.items() if not g)
            findings["guard-asymmetry"].append(f"{cid}: guarded on {on}, unguarded on {off}")

        has = {os: bool(r) for os, r in rems.items()}
        if len(set(has.values())) > 1 and any(has.values()):
            off = sorted(o for o, h in has.items() if not h)
            findings["rem-asymmetry"].append(f"{cid}: no remediation on {off}")

        for os, r in rems.items():
            if not isinstance(r, dict):
                continue
            # A shared, sticky directory (/tmp, /var/tmp, /dev/shm) MUST stay 1777: any other mode
            # means non-root users can no longer create files there. fileperm-unauthorized-world-
            # writable "remediated" itself with chmod 0775 /tmp, which would have broken the host.
            if (
                r.get("resource") == "file"
                and str(r.get("path")) in STICKY
                and str(r.get("mode", "")) not in ("1777", "01777")
            ):
                findings["sticky-dir"].append(
                    f"{cid} [{os}]: chmod {r.get('mode')} {r.get('path')} — must stay 1777"
                )
            # The check reads one literal file, the remediation writes another: the remediation
            # cannot make its own check pass. (Commands are excluded: auditing the EFFECTIVE config
            # while remediating through a drop-in is the intended pattern, not a defect.)
            m = re.search(r"describe file\('([^']+)'\)", " ".join(checks.get(os) or []))
            wrote = str(r.get("path") or r.get("file") or "")
            if m and wrote and wrote != m.group(1):
                findings["path-mismatch"].append(
                    f"{cid} [{os}]: check reads {m.group(1)}, remediation writes {wrote}"
                )

    total = 0
    for kind in (
        "ssg-leak",
        "bad-param",
        "sticky-dir",
        "path-mismatch",
        "guard-asymmetry",
        "rem-asymmetry",
    ):
        items = findings[kind]
        total += len(items)
        print(f"\n== {kind}: {len(items)}")
        for i in items[:25]:
            print(f"   {i}")
        if len(items) > 25:
            print(f"   ... and {len(items) - 25} more")

    print(f"\nTOTAL: {total} finding(s)")
    if "--strict" in sys.argv and total:
        sys.exit(1)


if __name__ == "__main__":
    main()
