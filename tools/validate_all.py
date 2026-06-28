#!/usr/bin/env python3
"""Industrialized validation dashboard: cross-validate pavois's CIS coverage for every
non-EOL OS against the consensus of independent authorities (SSG + ansible-lockdown), in one
run. Emits a table + a consolidated JSON (the trust artifact / API feed).

  tools/validate_all.py            # all configured OSes
"""
import json, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
# Auto-discover the OS list from the references pavois actually ships — the pipeline covers
# whatever is there, no hand-maintained list. EOL distros are dropped by name here.
EOL = set()  # add distros once past end-of-life (none yet among shipped refs)
OSES = sorted(p.stem for p in (ROOT / "docs/reference/pavois-content").glob("*.yml")
              if p.stem not in EOL)
# OSes CIS does not benchmark (no 2nd source can exist) — reported, not counted as a gap.
NO_CIS_BENCHMARK = {"fedora"}
rows, out = [], {}
for os in OSES:
    r = subprocess.run([sys.executable, str(ROOT/"tools/cross_validate.py"), os, "--json"],
                       capture_output=True, text=True)
    try:
        d = json.loads(r.stdout)
    except Exception:
        d = {"os": os, "consensus": 0, "pavois_covered": 0, "coverage_pct": None,
             "sources": {"ssg": 0, "ansible_lockdown": 0}, "gaps": [], "suspect_mappings": []}
    if os in NO_CIS_BENCHMARK:
        d["note"] = "no CIS benchmark exists for this distro (single-source by nature)"
    out[os] = d
    rows.append(d)
print(f"{'OS':<12} {'SSG':>4} {'AL':>4} {'consensus':>9} {'pavois':>7} {'cov%':>6} {'gaps':>5} {'suspect':>7}  note")
for d in rows:
    s = d.get("sources", {})
    note = "no CIS benchmark" if d["os"] in NO_CIS_BENCHMARK else (
        "SSG immature" if 0 < s.get("ssg", 0) < 50 else "")
    print(f"{d['os']:<12} {s.get('ssg',0):>4} {s.get('ansible_lockdown',0):>4} "
          f"{d.get('consensus',0):>9} {d.get('pavois_covered',0):>7} "
          f"{str(d.get('coverage_pct','-')):>6} {len(d.get('gaps',[])):>5} {len(d.get('suspect_mappings',[])):>7}  {note}")
(ROOT/"reports").mkdir(exist_ok=True)
(ROOT/"reports/validation-dashboard.json").write_text(json.dumps(out, indent=2))
print("\n-> reports/validation-dashboard.json")
