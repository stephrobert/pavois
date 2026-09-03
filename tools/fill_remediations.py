#!/usr/bin/env python3
"""Close the remediation holes: a control applicable to N OSes must be remediable on the N.

Root cause (see tools/gen.py `pick`): a remediation written `@os: {debian12: ...}` resolved to
None on every other OS and vanished from the render. Result: 123 of rhel10's 722 controls had NO
remediation, against 3 of debian12's 626. Most of those remediations are PORTABLE (a manual
procedure, a chmod, a systemctl call); they were simply keyed to the OS they were authored on.

This promotes a portable remediation to a SHARED value (no @os at all), so every applicable OS
gets it. It refuses to promote anything carrying a distro idiom (apt/dpkg vs dnf/rpm, nologin
path, PAM stack manager, firewall CLI): those need a real per-OS variant and are reported, never
guessed. Nothing here replaces the non-negotiable rule: a rules change is proven by a real scan.

Usage: tools/fill_remediations.py [--apply]   (default: dry-run report)
"""

import json
import sys
from collections import defaultdict

from ruamel.yaml import YAML

RULES = "docs/reference/rules.yml"

# Idioms that make a remediation distro-specific. If the text carries one, the value cannot be
# shared across families: it must be keyed per OS (or per family) by hand.
DEB = (
    "apt-get",
    "apt ",
    "dpkg",
    "/usr/sbin/nologin",
    "pam-auth-update",
    "common-password",
    "common-auth",
    "common-account",
    "update-rc.d",
    "debconf",
    "ufw",
    "/etc/default/grub.d",
)
EL = (
    "dnf ",
    "yum ",
    "authselect",
    "/sbin/nologin",
    "subscription-manager",
    "firewall-cmd",
    "semanage",
    "restorecon",
    "rpm ",
    "grub2-mkconfig",
    "system-auth",
    "password-auth",
)


def text(v):
    return json.dumps(v, sort_keys=True, default=str).lower()


def idioms(v):
    t = text(v)
    return sorted({w.strip() for w in DEB + EL if w in t})


def main():
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    yaml.representer.add_representer(
        type(None), lambda r, _: r.represent_scalar("tag:yaml.org,2002:null", "null")
    )
    with open(RULES) as f:
        d = yaml.load(f)

    promoted, divergent, distro, still = [], [], [], []
    for cid, e in d.items():
        if not isinstance(e, dict) or "applicable_os" not in e:
            continue
        oses = list(e["applicable_os"])
        r = e.get("remediation")
        if not isinstance(r, dict) or "@os" not in r:
            if not r:
                still.append(cid)  # no remediation anywhere: nothing to port, must be authored
            continue
        vals = r["@os"]
        missing = [o for o in oses if o not in vals]
        if not missing:
            continue
        distinct = {text(v) for v in vals.values()}
        if len(distinct) > 1:
            divergent.append(f"{cid}: {len(distinct)} variants, missing {missing}")
            continue
        v = next(iter(vals.values()))
        bad = idioms(v)
        if bad:
            distro.append(f"{cid}: authored for {sorted(vals)}, missing {missing} — idioms {bad}")
            continue
        e["remediation"] = v  # portable: share it, every applicable OS now has a remediation
        promoted.append(cid)

    print(f"PROMOTED to a shared remediation (portable): {len(promoted)}")
    for c in promoted[:15]:
        print("   ", c)
    if len(promoted) > 15:
        print(f"    ... and {len(promoted) - 15} more")
    print(f"\nNEEDS a per-OS variant (carries a distro idiom): {len(distro)}")
    for c in distro[:15]:
        print("   ", c)
    if len(distro) > 15:
        print(f"    ... and {len(distro) - 15} more")
    print(f"\nDIVERGENT values, needs a decision: {len(divergent)}")
    for c in divergent[:10]:
        print("   ", c)
    print(f"\nNO remediation at all (must be authored): {len(still)}")

    by_os = defaultdict(int)
    for e in d.values():
        if isinstance(e, dict) and "applicable_os" in e and not e.get("remediation"):
            for o in e["applicable_os"]:
                by_os[o] += 1
    print("\nremaining controls without a remediation, per OS:")
    for o, n in sorted(by_os.items()):
        print(f"   {o:<11} {n}")

    if "--apply" in sys.argv:
        with open(RULES, "w") as f:
            yaml.dump(d, f)
        print(f"\nwrote {RULES}")
    else:
        print("\n(dry-run: pass --apply to write)")


if __name__ == "__main__":
    main()
