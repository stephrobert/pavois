#!/usr/bin/env python3
"""Merge controls that audit exactly the same thing under different ids.

The project's own rule is: ONE control, N norm mappings: the norm is a view, never a copy. The
SSG bootstrap broke it: the same requirement arrived once per benchmark rule, so the base ended up
with nine /var/log controls for three actual audits, two ids for the same auditctl key, two ids for
the same pam_pwhistory line. They inflate the denominator, they are counted several times in the
grade, and worse, the duplicates DRIFTED: findloop-file-permissions-var-log auto-chmods what
findloop-file-permissions-unauthorized-world-writable declares too risky to auto-chmod.

This keeps the canonical id, UNIONS the norm mappings of the duplicates into it (nothing is lost:
the CIS/STIG/NIST refs of the merged ids follow), records `replaces:` for traceability, and deletes
the duplicates. It only merges controls whose rendered check is BYTE-IDENTICAL on every OS they
share: a difference of one character means it is not a duplicate, and it is left alone.

Usage: tools/merge_duplicates.py [--apply]
"""

import json
import sys
from pathlib import Path

from ruamel.yaml import YAML

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "docs" / "reference" / "rules.yml"
NORMS = ("bp28", "cis", "pci-dss", "nist", "stig")

# canonical id first; the others are merged into it and removed.
GROUPS = [
    # nine controls, three audits: group-ownership, ownership, permissions of /var/log
    (
        "findloop-file-groupowner-var-log",
        "findloop-file-groupownerships-var-log",
        "findloop-rsyslog-files-groupownership",
    ),
    (
        "findloop-file-owner-var-log",
        "findloop-file-ownerships-var-log",
        "findloop-rsyslog-files-ownership",
    ),
    (
        "findloop-permissions-local-var-log",
        "findloop-file-permissions-var-log",
        "findloop-rsyslog-files-permissions",
    ),
    # the same auditctl key, twice
    ("audit-kernel-module-loading", "audit-privileged-commands-rmmod"),
    ("audit-sysadmin-actions", "audit-sudoers"),
    # the same pam_pwhistory line, twice
    ("pam-pwhistory-enforce", "pam-pwhistory-enforce-for-root"),
    # the same InSpec code, line for line
    ("root-path", "root-path-no-dot"),
]


def as_list(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def main():
    y = YAML()
    y.preserve_quotes = True
    y.width = 4096
    y.representer.add_representer(
        type(None), lambda r, _: r.represent_scalar("tag:yaml.org,2002:null", "null")
    )
    d = y.load(RULES.read_text())

    merged, skipped = [], []
    for group in GROUPS:
        keep, dupes = group[0], group[1:]
        if keep not in d:
            skipped.append(f"{keep}: absent")
            continue
        for dup in dupes:
            e = d.get(dup)
            if e is None:
                continue
            # a duplicate must be an EXACT duplicate: same check on every shared OS
            shared = set(d[keep]["applicable_os"]) & set(e["applicable_os"])
            if not shared:
                skipped.append(f"{dup}: no OS in common with {keep}")
                continue
            if json.dumps(d[keep].get("check"), sort_keys=True, default=str) != json.dumps(
                e.get("check"), sort_keys=True, default=str
            ):
                skipped.append(f"{dup}: check differs from {keep}: NOT a duplicate, left alone")
                continue
            # the norm refs of the duplicate follow into the survivor: a merge loses no mapping
            for nm in NORMS:
                src = (e.get("norms") or {}).get(nm)
                if src is None:
                    continue
                dst = d[keep].setdefault("norms", {})
                cur = as_list(dst.get(nm))
                add = [x for x in as_list(src) if x is not None and x not in cur]
                if add:
                    vals = cur + add
                    dst[nm] = vals[0] if len(vals) == 1 else vals
            d[keep].setdefault("replaces", [])
            if dup not in d[keep]["replaces"]:
                d[keep]["replaces"].append(dup)
            del d[dup]
            merged.append(f"{dup} -> {keep}")

    print(f"merged {len(merged)} duplicate control(s):")
    for m in merged:
        print("  ", m)
    if skipped:
        print("\nleft alone:")
        for s in skipped:
            print("  ", s)
    if "--apply" in sys.argv:
        with RULES.open("w") as f:
            y.dump(d, f)
        print(f"\nwrote {RULES}")
    else:
        print("\n(dry-run: pass --apply)")


if __name__ == "__main__":
    main()
