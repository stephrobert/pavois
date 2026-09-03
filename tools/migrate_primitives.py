#!/usr/bin/env python3
"""Factorize rules.yml: collapse the @os blocks that differ ONLY by a known OS primitive.

The rule base carries ~950 @os blocks. Most of them are not real divergences of REQUIREMENT, they
are the same requirement written nine times with one distro-specific token swapped: the package
name (httpd vs apache2), the service name, the grub directory. Scattered like that, a wrong token
is invisible: that is exactly how RHEL package names sat in the debian columns for months, making
pkg-httpd-removed pass forever without proving anything.

So the token moves to ONE cell of ONE table (docs/reference/os/<os>.yml) and the control
references it as @{pkg.httpd}. A wrong fact is then fixed once, in a table you can read.

This script is deliberately timid: it rewrites nothing it cannot PROVE inert. Every candidate is
re-rendered for all its OSes and accepted only if the output is byte-identical to what the current
source produces. It does NOT fix any wrong value: it transports them faithfully. Corrections come
after, one by one, each with a real scan (the project's non-negotiable rule).

Usage: tools/migrate_primitives.py [--apply]     (default: dry-run report)
"""

import copy
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

from ruamel.yaml import YAML

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen  # noqa: E402  (reuse the real renderer: the proof must use the shipping code path)

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "docs" / "reference" / "rules.yml"
OSDIR = ROOT / "docs" / "reference" / "os"

# Which key of a @os block maps to which primitive namespace. `name` is the package or service
# name inside a remediation, so it follows the control's own family.
NAMESPACE = {"package": "pkg", "service": "svc"}


def slug(cid):
    """pkg-httpd-removed -> httpd ; service-dovecot-disabled -> dovecot"""
    s = re.sub(r"^(pkg|service)-", "", cid)
    return re.sub(r"-(removed|installed|disabled|enabled|masked)$", "", s).replace("-", "_")


def canon(v):
    return json.dumps(v, sort_keys=True, default=str)


def blocks(entry):
    for field in ("template", "remediation"):
        v = entry.get(field)
        if isinstance(v, dict) and "@os" in v:
            yield field, v


def differing(vals):
    """The keys whose value is not the same across every OS variant."""
    if not all(isinstance(v, dict) for v in vals.values()):
        return None
    keys = set().union(*[set(v) for v in vals.values()])
    return {k for k in keys if len({canon(v.get(k)) for v in vals.values()}) > 1}


def main():
    yml = YAML()
    yml.preserve_quotes = True
    yml.width = 4096
    yml.representer.add_representer(
        type(None), lambda r, _: r.represent_scalar("tag:yaml.org,2002:null", "null")
    )
    with open(RULES) as f:
        d = yml.load(f)

    lib = {k: v for k, v in d.items() if isinstance(v, dict) and "applicable_os" in v}
    before = gen.render(copy.deepcopy(lib))  # the reference render, from the shipping code path

    prims = defaultdict(dict)  # {"pkg.httpd": {os: "apache2", ...}}
    collapsed, factored, refused = [], [], []

    for cid, entry in lib.items():
        oses = list(entry["applicable_os"])
        for field, block in list(blocks(entry)):
            vals = block["@os"]
            if set(vals) != set(oses):  # partial block: fill_remediations handles those
                continue
            if len({canon(v) for v in vals.values()}) == 1:  # pure noise: nine copies of one value
                d[cid][field] = copy.deepcopy(next(iter(vals.values())))
                collapsed.append(f"{cid}.{field}")
                continue
            diff = differing(vals)
            if not diff or len(diff) != 1:
                continue
            key = next(iter(diff))
            ns = NAMESPACE.get(key)
            if ns is None and key == "name":  # a remediation naming a package or a service
                ns = (
                    "pkg"
                    if cid.startswith("pkg-")
                    else "svc"
                    if cid.startswith("service-")
                    else None
                )
            if ns is None:
                refused.append(f"{cid}.{field}: differs by `{key}` (no primitive yet)")
                continue
            prim = f"{ns}.{slug(cid)}"
            table = {os: vals[os][key] for os in oses}
            clash = {os: v for os, v in prims[prim].items() if os in table and table[os] != v}
            if clash:
                refused.append(f"{cid}.{field}: primitive {prim} already means {clash}")
                continue
            prims[prim].update(table)
            shared = copy.deepcopy(next(iter(vals.values())))
            shared[key] = f"@{{{prim}}}"
            d[cid][field] = shared
            factored.append(f"{cid}.{field} -> @{{{prim}}}")

    # MERGE the new primitives into the existing tables (never overwrite: a re-run must not wipe
    # facts an earlier run established, nor the corrections made by hand in the table since).
    allos = sorted({o for e in lib.values() for o in e["applicable_os"]})
    profiles = {}
    for os_ in allos:
        p = OSDIR / f"{os_}.yml"
        prof = yml.load(p.read_text()) if p.exists() else {}
        for prim, table in sorted(prims.items()):
            if os_ not in table:
                continue
            ns, name = prim.split(".", 1)
            prof.setdefault(ns, {}).setdefault(name, table[os_])
        profiles[os_] = prof

    gen.OS_PROFILES = {os_: json.loads(json.dumps(p, default=str)) for os_, p in profiles.items()}
    after = gen.render({k: v for k, v in d.items() if isinstance(v, dict) and "applicable_os" in v})
    moved = [
        f"{os_}/{cid}"
        for os_ in before
        for cid in before[os_]
        if canon(before[os_][cid]) != canon(after.get(os_, {}).get(cid))
    ]

    print(f"collapsed (identical across every OS, pure noise): {len(collapsed)}")
    print(f"factored into a primitive:                        {len(factored)}")
    for f_ in factored[:12]:
        print("   ", f_)
    if len(factored) > 12:
        print(f"    ... and {len(factored) - 12} more")
    print(f"refused (a real divergence, kept as @os):          {len(refused)}")
    print(f"\nprimitives created: {len(prims)}")
    verdict = f"RENDER MOVED for {len(moved)} controls" if moved else "\nRENDER IS BYTE-IDENTICAL"
    print(verdict)
    for m in moved[:10]:
        print("   ", m)

    if moved:
        sys.exit("refusing to write: the rewrite is NOT inert")
    if "--apply" not in sys.argv:
        print("\n(dry-run: nothing written; pass --apply)")
        return
    OSDIR.mkdir(parents=True, exist_ok=True)
    for os_, prof in profiles.items():  # write ONLY once the rewrite is proven inert
        if not prof:
            continue
        with open(OSDIR / f"{os_}.yml", "w") as f:
            f.write(
                "# OS primitives: the distro facts a control refers to as @{pkg.httpd}.\n"
                "# One cell = one fact, provable with one command (apt-cache policy).\n"
                "# A wrong cell breaks one control and is fixed HERE, not in 100 @os blocks.\n"
            )
            yml.dump(prof, f)
    with open(RULES, "w") as f:
        yml.dump(d, f)
    print(f"\nwrote {RULES} and {len(profiles)} OS profiles in {OSDIR}")


if __name__ == "__main__":
    main()
