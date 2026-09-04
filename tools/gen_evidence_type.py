#!/usr/bin/env python3
"""Classify every control by EVIDENCE TYPE: the keystone of the "opposable methodology" axis
(docs/site-review-chatgpt-2.md). A control's honesty depends on what kind of evidence its check
actually gathers; "effective configuration" is true for some checks, not all. We derive the type
from the check/template (the InSpec code never lies about what it reads) and write `evidence_type:`
into docs/reference/rules.yml: the DRY source: so it flows to the 8 OS files, the corpus tags,
the site fiches and OSCAL (where it replaces the blanket method=effective-config claim).

  tools/gen_evidence_type.py            # classify -> write evidence_type into rules.yml
  tools/gen_evidence_type.py --dry-run  # print distribution + unclassified, write nothing

Types (and what they honestly assert):
  effective-runtime  the resolved running state (sshd -T, sysctl, auditctl -l, systemctl show,
                     is-enabled/active, aa-status/getenforce, lsmod, /proc/mounts, kernel cmdline
                     of the booted kernel, compiled kconfig of the running kernel)
  persistent-config  the content of a persistent config file (login.defs, pwquality.conf, pam.d,
                     modprobe.d, sshd_config read as a file, audit rules on disk, grub, dconf)
  inventory-state    what is installed/registered (package present/absent, account databases)
  filesystem-state   a path's metadata (mode/owner/group, SUID/SGID, directory existence)
  manual             no machine check: human judgement / business context
  behavioral         an actively attempted forbidden action

Run after editing checks. The mapping is conservative: anything we cannot classify stays
`unclassified` and is reported (never silently bucketed), so a human resolves it.
"""

import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "reference" / "rules.yml"

# template name -> evidence type. Each template is ONE recurring check pattern, so its evidence
# kind is fixed (see tools/templates.py for what each expands to).
TEMPLATE_EVIDENCE = {
    "sysctl": "effective-runtime",  # `sysctl <key>` reads the live kernel value
    "kconfig": "effective-runtime",  # /boot/config-$(uname -r): the running kernel's build
    "service_disabled": "effective-runtime",  # systemctl is-enabled/is-active: resolved unit state
    "mount_option": "effective-runtime",  # parses the actually-mounted options
    "kmod_disabled": "effective-runtime",  # modprobe resolution + lsmod: the live module state
    "package": "inventory-state",  # package(...).installed?: what is registered
    "file_owner": "filesystem-state",  # file(...).mode/owner/group: path metadata
    "cmdline": "effective-runtime",  # /proc/cmdline: the booted kernel's command line
    "audit_rule": "effective-runtime",  # auditctl -l: the rules loaded in the live kernel
}

# Ordered signal table for verbatim checks. FIRST match wins, so order encodes precedence:
# runtime-resolved state is the strongest claim; file metadata beats file content; account
# databases are inventory; everything else that reads a config file is persistent-config.
SIGNALS = [
    (
        "effective-runtime",
        [
            "sshd -t",
            "sysctl",
            "auditctl",
            "systemctl show",
            "systemctl is",
            "is-enabled",
            "is-active",
            "aa-status",
            "getenforce",
            "sestatus",
            "lsmod",
            "nginx -t",
            "apachectl",
            "/proc/mounts",
            "/proc/cmdline",
            "chronyc",
            "timedatectl",
            "firewall-cmd",
            "ufw status",
            "nft list",
            "iptables",
            "ip6tables",
            "modprobe -c",
            "modprobe --showconfig",
            "authselect current",
            "grub2-editenv",
            "uname",
            "runtime",
            "mount(",
            "be_mounted",
            "service(",
            "be_enabled",
            "be_running",
            "kernel_parameter",
            "nmcli",
            "postconf",
        ],
    ),
    (
        "filesystem-state",
        [
            ".mode",
            ".owner",
            ".group",
            "be_owned_by",
            "grouped_into",
            "-perm",
            "suid",
            "sgid",
            "find /",
            "find -p",
            "! -user",
            "-user 0",
            "-user root",
            "-group ",
            "stat -c",
            "directory(",
            "be_directory",
            "have_mode",
        ],
    ),
    (
        "inventory-state",
        [
            "package(",
            "dpkg -l",
            "dpkg-query",
            "rpm -q",
            "/etc/passwd",
            "/etc/shadow",
            "/etc/group",
            "/etc/gshadow",
            "getent ",
            ".installed?",
            "command -v",
        ],
    ),
    (
        "persistent-config",
        [
            "login.defs",
            "login_defs",
            "/etc/default/",
            "pwquality",
            "faillock",
            "/etc/security",
            "modprobe.d",
            "/etc/ssh/sshd_config",
            "/etc/audit",
            "auditd.conf",
            "audit/rules",
            "grub",
            "parse_config",
            "/etc/pam",
            "/etc/sysctl",
            "limits.conf",
            "/etc/issue",
            "/etc/motd",
            "crontab",
            "/etc/cron",
            "dconf",
            "/etc/profile",
            "umask",
            "bashrc",
            "/etc/login",
            "journald.conf",
            "/etc/systemd/",
            "securetty",
            "sudoers",
            "/etc/shells",
            "gdm",
            "lightdm",
            "/etc/sssd",
            "file(",
        ],
    ),
]


def _pick(v):
    """Resolve an @os-keyed value to a representative concrete value (OS-stable classification)."""
    if isinstance(v, dict) and "@os" in v:
        for x in v["@os"].values():
            if x is not None:
                return x
        return None
    return v


def _check_text(e):
    c = _pick(e.get("check"))
    if isinstance(c, list):
        return "\n".join(str(x) for x in c)
    return str(c) if c else ""


def _template_name(e):
    t = _pick(e.get("template"))
    return t.get("name") if isinstance(t, dict) else None


def classify(e):
    tname = _template_name(e)
    if tname in TEMPLATE_EVIDENCE:
        return TEMPLATE_EVIDENCE[tname]
    text = _check_text(e).lower()
    if not text.strip():
        # no check body -> a manual/deliver-only control
        return "manual"
    if _pick(e.get("remediation")) == "manual" and "describe" not in text:
        return "manual"
    for etype, sigs in SIGNALS:
        if any(s in text for s in sigs):
            return etype
    return "unclassified"


def main():
    dry = "--dry-run" in sys.argv
    lib = yaml.safe_load(SRC.read_text())
    from collections import Counter

    dist = Counter()
    unclassified = []
    for cid, e in lib.items():
        et = classify(e)
        dist[et] += 1
        if et == "unclassified":
            unclassified.append(cid)
        else:
            e["evidence_type"] = et
    # unclassified controls are left WITHOUT the field (never guessed) and reported
    print("evidence_type distribution:")
    for et, n in dist.most_common():
        print(f"  {et:18} {n}")
    if unclassified:
        print(f"\n  UNCLASSIFIED ({len(unclassified)}): resolve by hand or extend SIGNALS:")
        for cid in unclassified[:40]:
            print(f"    {cid}")
        if len(unclassified) > 40:
            print(f"    … +{len(unclassified) - 40} more")
    if dry:
        print("\n(dry-run: rules.yml unchanged)")
        return 0
    SRC.write_text(yaml.safe_dump(lib, sort_keys=True, allow_unicode=True, width=4096))
    print(
        f"\nwrote evidence_type into {SRC.relative_to(ROOT)} "
        f"({sum(v for k, v in dist.items() if k != 'unclassified')}/{sum(dist.values())} "
        "classified)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
