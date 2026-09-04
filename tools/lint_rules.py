#!/usr/bin/env python3
"""Coherence linter for docs/reference/rules.yml: the guardrail that would have caught the
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

        # A control no OS runs is dead weight: it inflates the base, gets no page, and reads like a
        # missing fiche on the site.
        if not e.get("applicable_os"):
            findings["dead-rule"].append(f"{cid}: applicable_os is empty: no OS runs it")

        # YAML 1.1 (what pyyaml, hence gen.py, speaks) reads a bare `yes` as the BOOLEAN true. So
        # `reboot_survivable: yes` rendered as `true`, and the site: whose schema is the enum
        # yes|no|unknown: refused the whole build 800 pages later. Enum fields must be quoted.
        for f, allowed in (
            ("reboot_survivable", {"yes", "no", "unknown"}),
            ("remediation_class", {"auto", "dangerous", "install-time", "kernel-build", "manual"}),
            ("severity", {"low", "medium", "high", "critical"}),
        ):
            v = e.get(f)
            if v is None:
                continue
            if not isinstance(v, str):
                findings["enum-type"].append(
                    f"{cid}: {f} is {v!r} ({type(v).__name__}): quote it: "
                    "a bare `yes` is a BOOLEAN in YAML 1.1"
                )
            elif v not in allowed:
                findings["enum-type"].append(f"{cid}: {f}={v!r} is not one of {sorted(allowed)}")
        checks = per_os(e, "check")
        rems = per_os(e, "remediation")
        for os, tpl in per_os(e, "template").items():  # a templated check is still a check
            if isinstance(tpl, dict) and not checks.get(os):
                checks[os] = templates.expand(tpl)

        # A `template` OVERRIDES an explicit `check` at render (gen.py render()): the check is dead
        # code, and the control keeps auditing whatever the stale template says. That is how the
        # coredump control went on auditing a unit that exists nowhere after being rewritten.
        if e.get("check") and e.get("template"):
            findings["dead-check"].append(
                f"{cid}: has BOTH check and template: the check is ignored"
            )

        # primitive leak: the check resolves @{pkg.httpd} (apache2 on Debian) while the remediation
        # keeps the literal `httpd` shared by the nine OSes. pavois then audits the right package
        # and remediates one that exists on half the fleet. Both must resolve the same primitive.
        prim = None
        for tpl in per_os(e, "template").values():
            if isinstance(tpl, dict):
                for k in ("package", "service"):
                    v = str(tpl.get(k) or "")
                    if v.startswith("@{"):
                        prim = v
        if prim:
            for os, r in rems.items():
                if not isinstance(r, dict):
                    continue
                for k in ("name", "package"):
                    v = r.get(k)
                    if isinstance(v, str) and not v.startswith("@{"):
                        findings["primitive-leak"].append(
                            f"{cid} [{os}]: check uses {prim}, remediation hardcodes {v!r}"
                        )

        # pkg-mismatch: the check audits one package, the remediation installs/removes ANOTHER.
        # The remediation then cannot make its own check pass, and on a host where the name does
        # not exist it aborts the whole Chef run. pkg-nss-sss-installed audited `libnss-sss` (the
        # Debian name) and installed `nss-sss` (the RHEL one): invisible until a live apply.
        for os, tpl in per_os(e, "template").items():
            if not isinstance(tpl, dict) or tpl.get("name") != "package":
                continue
            audited = str(tpl.get("package") or "")
            r = rems.get(os)
            if not isinstance(r, dict) or r.get("resource") != "package":
                continue
            fixed = str(r.get("name") or r.get("package") or "")
            if audited and fixed and audited != fixed:
                findings["pkg-mismatch"].append(
                    f"{cid} [{os}]: audits {audited!r}, remediates {fixed!r}: "
                    "cannot pass its own check"
                )

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

        # A package installed from inside an `exec` (apt-get install -y acct) is invisible: it does
        # not appear in the plan, the operator never opts into it, and `harden rollback` cannot undo
        # it: it left acct and sysstat behind on a host it had "rolled back". The engine has a
        # declarative mechanism for exactly this (`requires_package`), and it must be used.
        for os, r in rems.items():
            if not isinstance(r, dict) or r.get("resource") != "exec":
                continue
            m = re.search(
                r"(?:apt-get|dnf|yum)\s+(?:-y\s+)?install\s+(?:-y\s+)?([a-z0-9][\w.+-]*)",
                str(r.get("command", "")),
            )
            if m:
                findings["exec-installs-package"].append(
                    f"{cid} [{os}]: an exec installs {m.group(1)!r}: declare it with "
                    "`requires_package` so the plan shows it and a rollback can undo it"
                )

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
                    f"{cid} [{os}]: chmod {r.get('mode')} {r.get('path')}: must stay 1777"
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

    # Two controls of the SAME exclusive group with DIFFERENT defaults make harden install two
    # technologies and (with the group resolved) disable each other's pick: a hardened host with
    # NO firewall at all. Measured on a clean-room debian12. One group, one default.
    import itertools

    excl = yaml.safe_load((ROOT / "docs" / "reference" / "exclusivity.yml").read_text()) or {}
    for gname, g in (excl.get("groups") or {}).items():
        defaults = {}
        gd = g.get("default") or {}
        for fam, tech in gd.items():
            defaults.setdefault(fam, set()).add(tech)
        for e in d.values():
            if not isinstance(e, dict) or e.get("exclusive_group") != gname:
                continue
            for r in per_os(e, "remediation").values():
                if isinstance(r, dict) and r.get("default"):
                    for fam in defaults:
                        defaults[fam].add(str(r["default"]))
        for fam, techs in defaults.items():
            if len(techs) > 1:
                findings["group-default"].append(
                    f"{gname} [{fam}]: two defaults {sorted(techs)}: harden sets up both, "
                    "and they cancel each other out"
                )
    _ = itertools

    total = 0
    for kind in (
        "exec-installs-package",
        "enum-type",
        "dead-rule",
        "group-default",
        "dead-check",
        "pkg-mismatch",
        "primitive-leak",
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
