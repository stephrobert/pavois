#!/usr/bin/env python3
"""DEV fix: collapse THRESHOLD merge_groups into a single control.

A value-per-norm split is only meaningful for mutually exclusive EXACT values. For
THRESHOLD checks (`deny <= 3` vs `deny <= 4`, `minlen >= 14` vs `>= 15`) the strictest
bound satisfies every norm (3 <= 3 and 3 <= 4), so the split is redundant AND incoherent
(both siblings end up tagged with the same norms). We keep only the STRICTEST variant,
retag it with the UNION of all siblings' norms/levels, drop the merge_group, and remove
the looser siblings.

Usage: tools/collapse_thresholds.py [<os> ...]   (default: all)
"""
import re
import sys
import yaml
from pathlib import Path
from collections import defaultdict

CONTENT = Path(__file__).resolve().parent.parent / "docs" / "reference" / "pavois-content"


def threshold(check):
    m = re.search(r"-le ([0-9]+)", check)
    if m:
        return ("le", int(m.group(1)))
    m = re.search(r"-ge ([0-9]+)", check)
    if m:
        return ("ge", int(m.group(1)))
    return None


def collapse(os_name):
    p = CONTENT / f"{os_name}.yml"
    lines = p.read_text().splitlines()
    header = "\n".join(l for l in lines[:3] if l.startswith("#")) + "\n"
    doc = yaml.safe_load(p.read_text())
    rules = doc["rules"]
    groups = defaultdict(list)
    for cid, e in rules.items():
        if e.get("merge_group"):
            groups[e["merge_group"]].append(cid)

    collapsed = 0
    for g, cids in groups.items():
        thrs = {c: threshold(" ".join(rules[c].get("check", []))) for c in cids}
        if not all(thrs.values()):
            continue  # not a pure threshold group (e.g. umask exact) — leave it
        dirs = {t[0] for t in thrs.values()}
        if len(dirs) != 1:
            continue
        d = dirs.pop()
        best = (min if d == "le" else max)(cids, key=lambda c: thrs[c][1])
        norms, levels = {}, {}
        for c in cids:
            norms.update(rules[c].get("norms", {}) or {})
            levels.update(rules[c].get("levels", {}) or {})
        surv = dict(rules[best])
        surv["norms"], surv["levels"] = norms, levels
        surv.pop("merge_group", None)
        surv["title"] = re.sub(r"\s*\([^)]*\)\s*$", "", surv.get("title", "")).strip()
        for c in cids:
            rules.pop(c, None)
        rules[g] = surv  # single, strictest, all-norms control keyed by the group name
        collapsed += 1

    p.write_text(header + yaml.safe_dump(doc, sort_keys=True, allow_unicode=True,
                                         default_flow_style=False, width=400), encoding="utf-8")
    print(f"{os_name}: collapsed {collapsed} threshold merge_group(s) -> {len(rules)} controls")


def main(args):
    for os in (args or [p.stem for p in sorted(CONTENT.glob("*.yml"))]):
        collapse(os)


if __name__ == "__main__":
    main(sys.argv[1:])
