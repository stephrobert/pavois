#!/usr/bin/env python3
"""Classify every control by REBOOT-SURVIVABILITY — the second axis of the qualified verdict
(docs/site-review-chatgpt-3.md, the headline chantier). evidence_type says WHAT a check reads;
this says whether a PASS proves a state that SURVIVES A REBOOT. The two are independent: a
runtime read can still be reboot-proof (a kernel's compiled config, `sshd -T` re-parsing the
config files) while another is purely live (`sysctl` of the running kernel, a live mount option).

We derive it from the same check/template signals (the InSpec code never lies about what it reads)
and write `reboot_survivable: yes|no|unknown` into docs/reference/rules.yml — the DRY source — so
it flows to the 8 OS files, the corpus tags (`tag reboot:`), the engine (audit.FullPass), the
fiches and OSCAL.

  tools/gen_reboot_survivable.py            # classify -> write reboot_survivable into rules.yml
  tools/gen_reboot_survivable.py --dry-run  # print distribution + the live set, write nothing

Values (and what they mean for grading):
  yes      a PASS proves a durable state (counts as a FULL pass)
  no       a PASS proves only the live state; persistence is NOT shown by this check — it needs a
           persistent companion (`requires_companion_control`) to become a full pass, else the
           grade is runtime-qualified (capped under A)
  unknown  cannot tell (manual / unclassified) — treated as not-full, never silently upgraded

The mapping is CONSERVATIVE: when in doubt we say `no`/`unknown`, never `yes`. Over-claiming
persistence is exactly the dishonesty this axis exists to kill.
"""
import sys
from collections import Counter
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "reference" / "rules.yml"

# template name -> reboot-survivability. See tools/templates.py for what each expands to.
TEMPLATE_REBOOT = {
    "package": "yes",            # installed/absent: registered state, survives reboot
    "file_owner": "yes",         # path mode/owner/group: on-disk metadata, survives reboot
    "kconfig": "yes",            # /boot/config-$(uname -r): the kernel binary's build — same after reboot
    "service_disabled": "yes",   # is-enabled: persistent unit enablement (masked/disabled survives)
    "sysctl": "yes",             # folded: asserts the LIVE value AND that it is pinned in /etc/sysctl.d → persists
    "mount_option": "yes",       # folded: asserts the live option AND that it is pinned in fstab/systemd → persists
    "kmod_disabled": "yes",      # not-loaded (live) AND be_disabled reads the persistent modprobe.d config → won't load on boot
    "cmdline": "yes",            # folded: asserts /proc/cmdline (live) AND the param pinned in grub → persists across reboot
    "audit_rule": "yes",         # folded: asserts the rule loaded live (auditctl -l) AND present in /etc/audit/rules.d → persists
}

# evidence_type -> reboot-survivability, for verbatim (non-template) checks. The durable-artifact
# types are reboot-proof by construction; effective-runtime is split by signal below.
EVIDENCE_REBOOT = {
    "persistent-config": "yes",  # reads a persistent config file on disk
    "inventory-state": "yes",    # installed/registered
    "filesystem-state": "yes",   # path metadata on disk
    "manual": "unknown",
    "behavioral": "no",          # proves the action is blocked NOW, not that it stays blocked after reboot
}

# Within effective-runtime, a check is reboot-proof only if it re-derives from a persistent source
# (config re-parse, the booted kernel's own build). FIRST match wins; live signals win ties so we
# never over-claim.
RUNTIME_LIVE = [
    "sysctl", "auditctl", "/proc/cmdline", "/proc/mounts", "mount(", "be_mounted", "getenforce",
    "aa-status", "sestatus", "lsmod", "is-active", "be_running", "firewall-cmd", "ufw status",
    "nft list", "iptables", "ip6tables", "kernel_parameter", "chronyc", "timedatectl", "nmcli",
    "modprobe -c", "modprobe --showconfig",
]
RUNTIME_PERSISTENT = [
    "sshd -t", "nginx -t", "apachectl", "/boot/config", "is-enabled", "be_enabled",
]


def _pick(v):
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
    if tname in TEMPLATE_REBOOT:
        return TEMPLATE_REBOOT[tname]
    ev = _pick(e.get("evidence_type"))
    if ev in EVIDENCE_REBOOT:
        return EVIDENCE_REBOOT[ev]
    if ev == "effective-runtime":
        text = _check_text(e).lower()
        if any(s in text for s in RUNTIME_LIVE):
            return "no"
        if any(s in text for s in RUNTIME_PERSISTENT):
            return "yes"
        return "no"  # conservative: an unrecognised runtime read is treated as live
    return "unknown"  # no evidence_type yet / unclassified — never guess yes


def main():
    dry = "--dry-run" in sys.argv
    lib = yaml.safe_load(SRC.read_text())
    dist = Counter()
    live = []
    for cid, e in lib.items():
        if not isinstance(e, dict):
            continue
        rs = classify(e)
        dist[rs] += 1
        if rs == "no":
            live.append(cid)
        e["reboot_survivable"] = rs
    print("reboot_survivable distribution:")
    for rs, n in dist.most_common():
        print(f"  {rs:8} {n}")
    print(f"\n  live set ({len(live)}) — these need a persistent companion to count as a full pass:")
    for cid in live[:30]:
        print(f"    {cid}")
    if len(live) > 30:
        print(f"    … +{len(live) - 30} more")
    if dry:
        print("\n(dry-run: rules.yml unchanged)")
        return 0
    SRC.write_text(yaml.safe_dump(lib, sort_keys=True, allow_unicode=True, width=4096))
    print(f"\nwrote reboot_survivable into {SRC.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
