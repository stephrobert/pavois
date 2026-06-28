#!/usr/bin/env python3
"""Coverage of an official benchmark by the pavois rule base — the artifact an auditor needs.

For one OS, it compares the CIS benchmark sections (the authoritative rule list, taken from the
SSG datastream as the best machine-readable proxy) against the cis mappings pavois's reference
carries. Reports per-chapter and overall coverage + the exact missing rules (pavois's gaps).

  tools/coverage_report.py <os> [--standard cis] [--datastream <path>] [--json]

The datastream is a VALIDATION ORACLE for the official rule list, NOT a dependency: pavois's
per-distro base is the source of truth; this just measures it against the published benchmark.
"""
import json
import re
import sys
import glob
from collections import defaultdict
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
OS = sys.argv[1]
STD = "cis"
JSON = "--json" in sys.argv
DS = None
if "--datastream" in sys.argv:
    DS = sys.argv[sys.argv.index("--datastream") + 1]
else:
    for c in (f"/tmp/oscap-analysis/ssg/ssg-{OS}-ds.xml", f"/tmp/oscap-analysis/ssg-{OS}-ds.xml",
              f"/tmp/ssgwork/ssg-{OS}-ds.xml"):
        if Path(c).exists():
            DS = c
            break
    DS = DS or next(iter(glob.glob(f"/tmp/**/ssg-{OS}-ds.xml", recursive=True)), None)

if not DS:
    sys.exit(f"no SSG datastream found for {OS} (pass --datastream)")

# 1) Official CIS rule list = the leaf sections the benchmark references (a section with no
#    deeper child is an actual rule; parents like '5.4' are chapter groupings).
xml = Path(DS).read_text(encoding="utf-8")
sections = set(re.findall(r"cisecurity[^>]*>(\d+(?:\.\d+)+)<", xml))
leaves = {s for s in sections if not any(o != s and o.startswith(s + ".") for o in sections)}

# 2) What pavois's base maps to CIS for this OS.
ref = yaml.safe_load((ROOT / "docs" / "reference" / "pavois-content" / f"{OS}.yml").read_text())["rules"]
pavois_cis = set()
for e in ref.values():
    v = (e.get("norms") or {}).get("cis")
    for x in (v if isinstance(v, list) else [v]):
        if x:
            pavois_cis.add(str(x))

covered = sorted(leaves & pavois_cis, key=lambda s: [int(x) for x in s.split(".")])
missing = sorted(leaves - pavois_cis, key=lambda s: [int(x) for x in s.split(".")])

by_chap = defaultdict(lambda: [0, 0])
for s in leaves:
    c = s.split(".")[0]
    by_chap[c][1] += 1
    if s in pavois_cis:
        by_chap[c][0] += 1

if JSON:
    print(json.dumps({"os": OS, "standard": STD, "datastream": DS,
                      "total": len(leaves), "covered": len(covered),
                      "coverage_pct": round(100 * len(covered) / max(1, len(leaves)), 1),
                      "by_chapter": {k: {"covered": v[0], "total": v[1]} for k, v in sorted(by_chap.items())},
                      "missing": missing, "covered_rules": covered}, indent=2))
else:
    print(f"CIS coverage — {OS}  (oracle: {Path(DS).name})\n")
    print(f"  Overall: {len(covered)}/{len(leaves)} rules covered "
          f"({round(100 * len(covered) / max(1, len(leaves)), 1)}%)\n")
    print("  By chapter:")
    for c, (cov, tot) in sorted(by_chap.items(), key=lambda x: int(x[0])):
        bar = "#" * round(20 * cov / tot)
        print(f"    {c:>2}  {cov:>3}/{tot:<3} {100*cov//tot:>3}%  {bar}")
    print(f"\n  Missing ({len(missing)} pavois gaps): " + ", ".join(missing[:40])
          + (" …" if len(missing) > 40 else ""))
