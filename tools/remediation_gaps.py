#!/usr/bin/env python3
"""Remediation-coverage gaps per OS.

For every control, for every OS in its `applicable_os`, check whether a remediation
actually RESOLVES for that OS (a flat `remediation`, or a `remediation['@os'][os]`).
A control that is applicable to an OS but has no remediation for it can never be
fixed on that OS -> a permanent FAIL (a parity hole).

Two buckets:
  PARITY  - the control HAS a remediation for at least one other OS: the fix exists,
            it just needs porting. This is the actionable stack to "depiler".
  ORPHAN  - no remediation for ANY OS: needs original remediation work (or is
            legitimately manual).

`evidence_type: manual|behavioral` controls are reported separately (NOT_REMEDIABLE):
they are audited, not auto-fixed, so a missing remediation is expected -- "os specific"
in the sense the user means (skip them).

Usage:
  python3 tools/remediation_gaps.py [os]        # summary, or detail for one OS
  python3 tools/remediation_gaps.py --parity     # only fillable parity gaps, all OS
"""

import sys

import yaml

RULES = "docs/reference/rules.yml"
OSES = [
    "debian12",
    "debian13",
    "ubuntu2204",
    "ubuntu2404",
    "rhel8",
    "rhel9",
    "fedora",
]
NOT_REMEDIABLE_EVIDENCE = {"manual", "behavioral"}


# resources that behave identically across distros -> a donor entry can be mirrored as-is
OS_AGNOSTIC = {
    "file",
    "directory",
    "sshd_setting",
    "sysctl",
    "keyval",
    "kernel_module",
    "selinux_state",
    "kernel_cmdline",
    "audit_ruleset",
    "grub_password",
    "conf_line",
    "pam_module",
}
# donor resources that porting does NOT help: manual stays manual; kernel_build is a
# single OS kernel recipe (el8 option limits are real, not a parity hole).
NOT_FILLABLE_RESOURCE = {"manual", "kernel_build"}


def resolves(c, os):
    """Does a remediation resolve for this OS?"""
    rem = c.get("remediation")
    if not rem:
        return False
    if isinstance(rem, dict) and "@os" in rem:
        sub = rem["@os"]
        return isinstance(sub, dict) and sub.get(os) is not None
    return True  # flat remediation applies to all OSes


def donor_resource(c, os):
    """Resource type of the donor remediation for `os` (the first OS that resolves)."""
    rem = c.get("remediation") or {}
    for o in OSES:
        if not resolves(c, o):
            continue
        r = rem["@os"][o] if "@os" in rem else rem
        if isinstance(r, dict):
            return r.get("resource", "?")
    return "?"


def main():
    with open(RULES) as f:
        d = yaml.safe_load(f)
    only = None
    parity_only = False
    for a in sys.argv[1:]:
        if a == "--parity":
            parity_only = True
        elif a in OSES:
            only = a

    # per-OS buckets
    parity = {o: [] for o in OSES}  # fillable: fix exists elsewhere and is portable
    orphan = {o: [] for o in OSES}  # no remediation anywhere (original work needed)
    manual = {o: [] for o in OSES}  # manual/behavioral, or manual/kernel_build donor: skip
    for cid in sorted(d):
        c = d[cid]
        aos = c.get("applicable_os") or []
        ev = c.get("evidence_type", "")
        has_any = any(resolves(c, o) for o in OSES)
        for o in aos:
            if o not in OSES or resolves(c, o):
                continue
            if ev in NOT_REMEDIABLE_EVIDENCE:
                manual[o].append(cid)
            elif has_any:
                if donor_resource(c, o) in NOT_FILLABLE_RESOURCE:
                    manual[o].append(cid)  # manual/kernel_build donor: porting doesn't help
                else:
                    parity[o].append((cid, ev))
            else:
                orphan[o].append((cid, ev))

    def show(o):
        print(f"\n=== {o} ===")
        print(f"  PARITY gaps (fix exists elsewhere, port it): {len(parity[o])}")
        # split by whether the donor remediation is OS-agnostic (mirror) or needs translation
        mir = [(c, e) for c, e in parity[o] if donor_resource(d[c], o) in OS_AGNOSTIC]
        xlate = [(c, e) for c, e in parity[o] if donor_resource(d[c], o) not in OS_AGNOSTIC]
        print(f"    -- MIRRORABLE (OS-agnostic donor): {len(mir)}")
        for cid, _ev in mir:
            print(f"       {cid:40} [{donor_resource(d[cid], o)}]")
        print(f"    -- NEEDS TRANSLATION (package/exec/choose): {len(xlate)}")
        for cid, _ev in xlate:
            print(f"       {cid:40} [{donor_resource(d[cid], o)}]")
        if not parity_only:
            print(f"  ORPHAN (no remediation anywhere): {len(orphan[o])}")
            for cid, ev in orphan[o]:
                print(f"    {cid:42} [{ev}]")
            print(f"  not-remediable (manual/behavioral, skip): {len(manual[o])}")

    targets = [only] if only else OSES
    if not only:
        print("REMEDIATION-COVERAGE SUMMARY  (parity = actionable stack)")
        print(f"{'OS':12} {'parity':>7} {'orphan':>7} {'manual':>7}")
        for o in OSES:
            print(f"{o:12} {len(parity[o]):>7} {len(orphan[o]):>7} {len(manual[o]):>7}")
    for o in targets:
        show(o)


if __name__ == "__main__":
    main()
