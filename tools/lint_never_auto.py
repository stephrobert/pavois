#!/usr/bin/env python3
"""Rules whose remediation must never run unattended, and why.

`harden plan --enable auto` arms every gap whose remediation class is `auto`. That is the right
default for the overwhelming majority, and catastrophic for a handful whose fix cannot be decided
without knowledge Pavois does not carry. Each entry below cost, or would have cost, a machine.

A class is a single word in a 40k-line YAML file. Changing one back to `auto` is a one-character
edit that no test would otherwise notice, so this pins them with the reason attached.

  mise run lint:never-auto
"""

from __future__ import annotations

import sys

import yaml

RULES = "docs/reference/rules.yml"

# rule id -> (allowed classes, why it must not be armed automatically)
NEVER_AUTO = {
    "findloop-file-groupownership-system-commands-dirs": (
        {"manual"},
        "chowns root:root every binary whose user OR group is not root, and a setgid binary "
        "derives its privilege FROM its group. On a stock Debian that takes unix_chkpwd "
        "(root:shadow) and password authentication stops working. Also crontab, at, ssh-agent.",
    ),
    "kmod-loading-disabled": (
        {"dangerous", "manual"},
        "kernel.modules_disabled=1 stops every later module load, which can strand the nftables "
        "firewall when nf_conntrack is not resident yet: no `ct state` rule, no SSH.",
    ),
    "kmod-overlayfs-disabled": (
        {"dangerous", "manual"},
        "breaks container runtimes and any overlay-based root filesystem.",
    ),
    "sudo-noexec": (
        {"dangerous", "manual"},
        "`Defaults noexec` forbids a sudo command from executing another one, and a package "
        "manager execs its own helpers: `sudo apt-get install` fails on dpkg-preconfigure, "
        "measured on a clean Ubuntu 24.04. A machine whose operator cannot install a package is "
        "not administrable. The control itself is sound (vi and less genuinely cannot shell out "
        "under it, measured against a control group), so it is held back rather than dropped, and "
        "its remediation carves out the package managers explicitly.",
    ),
    "sudo-requiretty": (
        {"dangerous", "manual"},
        "Defaults requiretty forbids every sudo without a terminal: Ansible without a pty, cron, "
        "CI runners, and Pavois itself, which can then no longer re-scan the host it hardened.",
    ),
    "service-fapolicyd-enabled": (
        {"dangerous", "manual"},
        "fapolicyd denies every execution its trust database does not list. Enabled by an apply "
        "on AlmaLinux 8 it blocked /usr/sbin/auditd from opening its own config: auditd never "
        "started and 21 audit controls failed (#166). Running `fapolicyd-cli --update` first is "
        "not enough when a daemon ships an interpreter or plugin outside the RPM set, and the "
        "denial shows only in /var/log/fapolicyd-access.log. The operator opts in after a "
        "permissive-mode validation.",
    ),
    "pkg-fapolicyd-installed": (
        {"dangerous", "manual"},
        "the first half of the change above, with the same danger note: the package lands with no "
        "trust database built, so whoever enables the service next inherits the denials. Armed "
        "knowingly, together with the service, never by --enable auto.",
    ),
}


def main() -> int:
    with open(RULES, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    rules = doc["rules"] if isinstance(doc, dict) and "rules" in doc else doc

    problems: list[str] = []
    for rid, (allowed, why) in NEVER_AUTO.items():
        rule = rules.get(rid)
        if rule is None:
            problems.append(
                f"{rid}: pinned here but gone from the rule base"
                " (remove the pin, or restore the rule)"
            )
            continue
        cls = rule.get("remediation_class")
        if cls not in allowed:
            problems.append(
                f"{rid}: remediation_class is {cls!r},"
                f" expected one of {sorted(allowed)}\n      {why}"
            )
        if cls != "manual" and not rule.get("danger"):
            problems.append(
                f"{rid}: classed {cls!r} with no `danger:` note, so nothing tells the operator why"
            )

    print(f"lint:never-auto: {len(NEVER_AUTO)} pinned rule(s) checked")
    if problems:
        print(f"lint:never-auto: {len(problems)} regression(s)", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        print(
            "\n  These remediations are held back on purpose. If one is safe now, prove it\n"
            "  with a real apply on a live host, then remove its pin here in the same commit.",
            file=sys.stderr,
        )
        return 1
    print("lint:never-auto: every dangerous remediation is still held back")
    return 0


if __name__ == "__main__":
    sys.exit(main())
