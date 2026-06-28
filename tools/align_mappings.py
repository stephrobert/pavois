#!/usr/bin/env python3
"""Re-align the norm mappings (cis/bp28/nist/pci-dss/stig) of pavois's reference to the CURRENT
official benchmark, using the SSG datastream as the source of the up-to-date references.

pavois was bootstrapped from an older SSG, so some mappings drifted (e.g. CIS renumbered the
audit chapter 6.x -> 8.x/10.x). For every pavois control that carries an `ssg` rule id, we look
up that SSG rule's CURRENT references in the datastream and overwrite pavois's norms with them
(real, never invented). Pavois-owned rules with no `ssg` are left untouched.

  tools/align_mappings.py <os> [--datastream <path>] [--dry-run]
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
OS = sys.argv[1]
DRY = "--dry-run" in sys.argv
DS = (sys.argv[sys.argv.index("--datastream") + 1] if "--datastream" in sys.argv else None)
if not DS:
    for c in (f"/tmp/oscap-analysis/ssg/ssg-{OS}-ds.xml", f"/tmp/oscap-analysis/ssg-{OS}-ds.xml",
              f"/tmp/ssgwork/ssg-{OS}-ds.xml",
              f"/tmp/oscap-analysis/scap-security-guide-0.1.81/ssg-{OS}-ds.xml"):
        if Path(c).exists():
            DS = c
            break
if not DS or not Path(DS).exists():
    sys.exit(f"no SSG datastream for {OS}")

xml = Path(DS).read_text(encoding="utf-8")

# Per SSG rule -> its current references, classified by norm.
rule_norms = {}
for blk in re.split(r"(?=<[\w.:-]*Rule\s)", xml)[1:]:
    m = re.search(r'id="[^"]*content_rule_([\w-]+)"', blk)
    if not m:
        continue
    end = re.search(r"</[\w.:-]*Rule>", blk)
    seg = blk[: end.start()] if end else blk
    cis, bp28, nist, stig, pci = [], [], [], [], []
    for href, val in re.findall(r'<[\w.:-]*reference[^>]*href="([^"]+)"[^>]*>([^<]+)</', seg):
        val = val.strip()
        if "cisecurity" in href and re.match(r"^\d+(\.\d+)+$", val):
            cis.append(val)
        elif "ssi.gouv" in href or "anssi" in href.lower():
            bp28.append(val)
        elif "nist" in href and re.match(r"^[A-Z]{2}-\d", val):
            nist.append(val)
        elif "disa" in href or "stigid" in href.lower():
            stig.append(val)
        elif "pci" in href.lower():
            pci.append(val)
    norms = {}
    if cis:  # keep the most-specific (leaf) CIS section(s)
        leaves = [s for s in set(cis) if not any(o != s and o.startswith(s + ".") for o in cis)]
        norms["cis"] = leaves[0] if len(leaves) == 1 else sorted(leaves)
    for k, vals in (("bp28", bp28), ("nist", nist), ("stig", stig), ("pci-dss", pci)):
        u = list(dict.fromkeys(vals))
        if u:
            norms[k] = u[0] if len(u) == 1 else u
    rule_norms[m.group(1)] = norms

p = ROOT / "docs" / "reference" / "pavois-content" / f"{OS}.yml"
d = yaml.safe_load(p.read_text())
aligned = changed = 0
for cid, e in d["rules"].items():
    ssg = e.get("ssg")
    if not ssg or ssg not in rule_norms:
        continue
    new = rule_norms[ssg]
    if not new:
        continue
    aligned += 1
    if e.get("norms") != new:
        changed += 1
    e["norms"] = {**(e.get("norms") or {}), **new}
if not DRY:
    p.write_text(yaml.safe_dump(d, sort_keys=False, allow_unicode=True))
print(f"{OS}: {aligned} controls had an ssg match, {changed} mappings re-aligned to current SSG "
      f"({'dry-run' if DRY else 'written'})")
