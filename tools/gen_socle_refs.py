#!/usr/bin/env python3
"""Assign each control a SOCLE reference — pavois is the executable Linux-host audit profile of the
SOCLE norm (framework-scsl). A control becomes a leaf requirement under SOCLE's RUN (runtime/observ-
ability) and CLD (host/infra posture) domains, with a pavois technical family. Format, the SOCLE
scheme verbatim: SOCLE-<DOMAIN>-<FAMILY>-<NNN>.

Writes `socle:` into docs/reference/rules.yml (the DRY source) and emits a {control_id: socle} map
to site/src/data/socle-refs.json for the site. Sequences are stable (deterministic by id within a
family); new controls append. Servers, not workstations -> WKS is unused; everything lands RUN/CLD.
Run once, then on every new control. See docs/site-enrichment.md and framework-scsl/source/.
"""

import json
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "reference" / "rules.yml"
MAP_OUT = ROOT / "site" / "src" / "data" / "socle-refs.json"

# pavois domain -> (SOCLE domain, pavois technical family). Validated mapping.
DOMAIN_MAP = {
    "Audit (auditd)": ("RUN", "AUD"),
    "Audit (auditd daemon)": ("RUN", "AUD"),
    "Logging (journald)": ("RUN", "LOG"),
    "Logging": ("RUN", "LOG"),
    "systemd services": ("RUN", "SVC"),
    "Time synchronization": ("RUN", "NTP"),
    "SSH": ("CLD", "SSH"),
    "Kernel & network (sysctl)": ("CLD", "SYS"),
    "Kernel build": ("CLD", "KRN"),
    "Kernel command line": ("CLD", "KRN"),
    "Kernel modules": ("CLD", "MOD"),
    "File permissions": ("CLD", "FSP"),
    "File ownership": ("CLD", "FSP"),
    "Filesystem (scan)": ("CLD", "FSP"),
    "Packages": ("CLD", "PKG"),
    "Mounts": ("CLD", "MNT"),
    "Firewall": ("CLD", "NET"),
    "Bootloader (grub)": ("CLD", "BOOT"),
    "Accounts": ("CLD", "IAM"),
    "Accounts (PAM modules)": ("CLD", "IAM"),
    "Accounts (login.defs)": ("CLD", "IAM"),
    "Accounts (faillock)": ("CLD", "IAM"),
    "Accounts (home dirs)": ("CLD", "IAM"),
    "Accounts (umask)": ("CLD", "IAM"),
    "Accounts (password history)": ("CLD", "IAM"),
    "Accounts (root PATH)": ("CLD", "IAM"),
    "Passwords (pwquality)": ("CLD", "IAM"),
    "Sudo": ("CLD", "IAM"),
    "Banners": ("CLD", "GEN"),
    "GNOME desktop (dconf)": ("CLD", "GEN"),
    "Cron/at access control": ("CLD", "GEN"),
    "Hardening (misc)": ("CLD", "GEN"),
    "Hardening (posture)": ("CLD", "GEN"),
}
FALLBACK = ("CLD", "GEN")


def get_domain(e):
    d = e.get("domain")
    if isinstance(d, dict) and "@os" in d:
        return next(iter(d["@os"].values()), None)
    return d


def main():
    lib = yaml.safe_load(SRC.read_text())
    # group control ids by (SOCLE domain, family)
    buckets = {}
    for cid, e in lib.items():
        dom = get_domain(e)
        sd, fam = DOMAIN_MAP.get(dom, FALLBACK)
        buckets.setdefault((sd, fam), []).append(cid)

    refmap = {}
    for (sd, fam), cids in buckets.items():
        for i, cid in enumerate(sorted(cids), 1):
            refmap[cid] = f"SOCLE-{sd}-{fam}-{i:03d}"

    for cid, e in lib.items():
        e["socle"] = refmap[cid]

    SRC.write_text(yaml.safe_dump(lib, sort_keys=True, allow_unicode=True, width=4096))
    MAP_OUT.write_text(json.dumps(refmap, ensure_ascii=False, indent=0, sort_keys=True) + "\n")

    from collections import Counter

    fam = Counter(r.rsplit("-", 1)[0] for r in refmap.values())
    print(f"socle: {len(refmap)} controls -> {len(fam)} families")
    for f, n in sorted(fam.items()):
        print(f"  {f:<16} {n}")


if __name__ == "__main__":
    main()
