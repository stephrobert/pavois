#!/usr/bin/env python3
"""Keep applicability declared, and keep the old way from growing back.

`applies_if` (#324) replaces four unrelated mechanisms that each answered "does this requirement
apply to this host?". Replacing them is a long job, and a long job without a ratchet is a job that
never finishes: while the 90 hand-written `only_if` guards below get migrated, nothing stopped a
91st from being written next to them.

Three rules, and each one is a thing that has actually happened or is about to:

1. **Every `applies_if` is well formed.** The vocabulary is closed and `because:` is mandatory,
   both already enforced by tools/applies_if.py. Nothing ran that check over rules.yml: the module
   only validated itself, so a malformed block in the source was found at render time at best.

2. **No NEW hand-written `only_if`.** MIGRATING is the exact list of the controls that still carry
   one. A control not on it that grows one is refused, with the `applies_if` block it should have
   written instead. A control ON it that no longer carries one is ALSO refused: the entry is stale,
   and a worklist that keeps entries it has finished stops being a worklist. So the list can only
   shrink, and the day it is empty this rule turns into "no hand-written only_if at all".

3. **Never both mechanisms on one control.** A control that declares `applies_if` and also hides an
   `only_if` in its check has two answers to one question, and the reader cannot tell which one
   fired. There are zero today: this rule starts at zero and stays there.

What this linter deliberately does NOT refuse: `applies_if` together with a `waiver`. They say
different, compatible things. `mount-var-noexec` declares that CIS words the requirement "IF a
separate partition exists for /var", AND that where it does apply the risk is accepted because
noexec on /var leaves apt and dnf unable to patch the machine. Dropping either one loses a fact.
The runtime is what must be unambiguous, and it is: a waiver wins, because a waiver is the
statement an auditor can refuse. That is frozen by a Go test, not here.
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import applies_if  # noqa: E402  the closed vocabulary itself

RULES = Path(__file__).resolve().parent.parent / "docs" / "reference" / "rules.yml"

# The controls that still answer applicability with a hand-written `only_if`, measured on
# 2026-09-18. This is the #324 worklist, and it may only shrink. Grouped the way the migration
# will happen, because they do not all become the same predicate:
#
#   dconf-gnome-*     `only_if { command('dconf').exist? }`   ->  command: dconf
#   file*             `only_if { file('<p>').exist? }`        ->  path: <p>
#   the last three    one-off conditions, each its own decision
#
# Every one of them needs the norm's OWN wording in its `because:`, which is the part no script can
# do: "the file is absent" is a fact, "CIS words this IF the file exists" is a source. Migrating
# without the source would turn a guard into a silent pass, which is the whole risk #324 names.
MIGRATING = {
    # GNOME desktop settings: meaningless where dconf is not installed.
    "dconf-gnome-banner-enabled",
    "dconf-gnome-disable-automount",
    "dconf-gnome-disable-automount-open",
    "dconf-gnome-disable-autorun",
    "dconf-gnome-disable-ctrlaltdel-reboot",
    "dconf-gnome-disable-restart-shutdown",
    "dconf-gnome-disable-user-list",
    "dconf-gnome-lock-screen-on-smartcard-removal",
    "dconf-gnome-login-banner-text",
    "dconf-gnome-login-retries",
    "dconf-gnome-screensaver",
    "dconf-gnome-screensaver-idle-activation-enabled",
    "dconf-gnome-screensaver-idle-delay",
    "dconf-gnome-screensaver-lock-enabled",
    "dconf-gnome-screensaver-lock-locked",
    "dconf-gnome-screensaver-mode-blank",
    "dconf-gnome-screensaver-user-info",
    "dconf-gnome-screensaver-user-locks",
    "dconf-gnome-session-idle-user-locks",
    # File ownership and permissions, guarded on the file existing.
    "filegroupowner-cron-allow",
    "filegroupowner-var-log-lastlog",
    "fileowner-var-log-auth",
    "fileowner-var-log-cloud-init",
    "fileowner-var-log-localmessages",
    "fileowner-var-log-messages",
    "fileowner-var-log-secure",
    "fileowner-var-log-syslog",
    "fileowner-var-log-waagent",
    "fileperm-at-allow",
    "fileperm-at-deny",
    "fileperm-audit-binaries",
    "fileperm-backup-etc-group",
    "fileperm-backup-etc-passwd",
    "fileperm-boot-grub2",
    "fileperm-cron-allow",
    "fileperm-cron-d",
    "fileperm-cron-daily",
    "fileperm-cron-hourly",
    "fileperm-cron-monthly",
    "fileperm-cron-weekly",
    "fileperm-cron-yearly",
    "fileperm-crontab",
    "fileperm-etc-audit-auditd",
    "fileperm-etc-audit-rules",
    "fileperm-etc-crypttab",
    "fileperm-etc-group",
    "fileperm-etc-ipsec-conf",
    "fileperm-etc-ipsec-secrets",
    "fileperm-etc-ipsecd",
    "fileperm-etc-issue",
    "fileperm-etc-issue-net",
    "fileperm-etc-motd",
    "fileperm-etc-passwd",
    "fileperm-etc-security-opasswd",
    "fileperm-etc-security-opasswd-old",
    "fileperm-etc-selinux",
    "fileperm-etc-sestatus-conf",
    "fileperm-etc-shells",
    "fileperm-etc-sudoers",
    "fileperm-etc-sudoersd",
    "fileperm-etc-sysconfig-sshd",
    "fileperm-etc-sysctld",
    "fileperm-journalctl",
    "fileperm-library-dirs",
    "fileperm-sshd-config",
    "fileperm-sshd-config-d",
    "fileperm-sshd-drop-in-config",
    "fileperm-var-log-apt",
    "fileperm-var-log-audit",
    "fileperm-var-log-auth",
    "fileperm-var-log-gdm",
    "fileperm-var-log-gdm3",
    "fileperm-var-log-lastlog",
    "fileperm-var-log-localmessages",
    "fileperm-var-log-messages",
    "fileperm-var-log-sssd",
    "fileperm-var-log-syslog",
    "groupowner-var-log-journal",
    "groupownerships-var-log-gdm",
    "groupownerships-var-log-gdm3",
    "groupownerships-var-log-sssd",
    "owner-var-log-journal",
    "ownership-library-dirs",
    "ownerships-var-log-gdm",
    "ownerships-var-log-gdm3",
    "ownerships-var-log-sssd",
    # One-offs, each needing its own reading of the norm.
    "journald-forward-to-running-syslog",
    "journald-forwardtosyslog",
    "misc-sssd-ldap-start-tls",
    "service-syslogng-enabled",
}


def check_lines(entry: dict) -> list[str]:
    """Every line of a control's `check:`, whatever the @os keying looks like.

    A check may be a list, a string, or a mapping keyed by OS. Reading only the list form is how a
    guard hides: the OS-keyed controls are exactly the ones whose applicability differs per system.
    """
    chk = entry.get("check")
    if isinstance(chk, str):
        return [chk]
    if isinstance(chk, list):
        return [x for x in chk if isinstance(x, str)]
    if isinstance(chk, dict):
        out: list[str] = []
        for v in chk.values():
            if isinstance(v, str):
                out.append(v)
            elif isinstance(v, list):
                out.extend(x for x in v if isinstance(x, str))
        return out
    return []


def load(path: Path) -> dict:
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    rules = doc.get("rules") if isinstance(doc, dict) else None
    return rules if isinstance(rules, dict) else (doc if isinstance(doc, dict) else {})


def problems(rules: dict) -> list[str]:
    bad: list[str] = []
    seen_handwritten: set[str] = set()

    for cid, entry in sorted(rules.items()):
        if not isinstance(entry, dict):
            continue

        conds = entry.get("applies_if")
        if conds:
            bad.extend(applies_if.problems(cid, conds))

        handwritten = [ln for ln in check_lines(entry) if "only_if" in ln]
        if not handwritten:
            continue
        seen_handwritten.add(cid)

        if conds:
            bad.append(
                f"{cid}: declares applies_if AND hides a hand-written only_if in its check. "
                f"One control, one answer: move the guard into applies_if."
            )
        elif cid not in MIGRATING:
            bad.append(
                f"{cid}: a NEW hand-written only_if. Applicability is declared now:\n"
                f"        applies_if:\n"
                f"          - <predicate>: <value>\n"
                f"            because: '<the norm wording that makes this conditional>'\n"
                f"        (vocabulary: {', '.join(sorted(applies_if.VOCABULARY))})\n"
                f"        the guard found: {handwritten[0].strip()[:90]}"
            )

    for cid in sorted(MIGRATING - seen_handwritten):
        where = "no longer exists" if cid not in rules else "no longer carries one"
        bad.append(
            f"{cid}: listed as still carrying a hand-written only_if, but it {where}. "
            f"Remove it from MIGRATING in tools/lint_applies_if.py: a worklist that keeps "
            f"finished entries stops being a worklist."
        )
    return bad


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()

    rules = load(RULES)
    if not rules:
        print(f"lint:applies-if: {RULES} holds no rules", file=sys.stderr)
        return 2

    bad = problems(rules)
    declared = sum(1 for e in rules.values() if isinstance(e, dict) and e.get("applies_if"))
    if bad:
        for b in bad:
            print(f"  {b}")
        print(f"\nlint:applies-if: {len(bad)} problem(s)")
        return 1
    print(
        f"lint:applies-if: clean. {declared} control(s) declare applicability, "
        f"{len(MIGRATING)} still to migrate."
    )
    return 0


def selftest() -> int:
    """Plant one defect per rule and demand red, then demand silence on the corrected witness.

    A linter nobody has seen fail is a linter nobody should trust.
    """
    ok = True

    def expect(name: str, rules: dict, want_hit: str | None) -> None:
        nonlocal ok
        hits = problems(rules)
        if want_hit is None:
            if hits:
                print(f"  FAIL {name}: expected silence, got {hits}")
                ok = False
            else:
                print(f"  ok   {name}: silent, as it must be")
            return
        if any(want_hit in h for h in hits):
            print(f"  ok   {name}: caught")
        else:
            print(f"  FAIL {name}: expected a hit containing {want_hit!r}, got {hits}")
            ok = False

    # Every planted case keeps MIGRATING satisfied, so only the defect under test can fire.
    filler = {cid: {"check": ["only_if { file('/x').exist? }"]} for cid in MIGRATING}

    expect(
        "a malformed applies_if (no because)",
        {**filler, "zz-new": {"applies_if": [{"mount": "/srv"}]}},
        "no `because`",
    )
    expect(
        "a predicate outside the vocabulary",
        {**filler, "zz-new": {"applies_if": [{"shell": "test -x /x", "because": "b"}]}},
        "unknown predicate",
    )
    expect(
        "a NEW hand-written only_if",
        {**filler, "zz-new": {"check": ["only_if { file('/etc/x').exist? }"]}},
        "a NEW hand-written only_if",
    )
    expect(
        "a new one hidden in an @os-keyed check",
        {**filler, "zz-new": {"check": {"debian12": ["only_if { command('x').exist? }"]}}},
        "a NEW hand-written only_if",
    )
    expect(
        "both mechanisms on one control",
        {
            **filler,
            "zz-new": {
                "applies_if": [{"path": "/etc/x", "because": "CIS 1.2.3"}],
                "check": ["only_if { file('/etc/x').exist? }"],
            },
        },
        "declares applies_if AND hides",
    )
    stale = dict(filler)
    stale.pop(sorted(MIGRATING)[0])
    expect("a stale MIGRATING entry", stale, "Remove it from MIGRATING")

    # The witness, in both directions: a correct applies_if, and a waiver alongside it, which is
    # explicitly allowed. Without this half, a linter that refused everything would look perfect.
    expect(
        "a correct applies_if, with a waiver next to it",
        {
            **filler,
            "zz-new": {
                "applies_if": [
                    {"mount": "/var", "because": 'CIS 1.1.2.x: "IF a separate partition"'}
                ],
                "waiver": "noexec on /var breaks apt: accepted risk",
                "check": ["describe mount('/var') do", "end"],
            },
        },
        None,
    )

    print("selftest: PASS" if ok else "selftest: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
