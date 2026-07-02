#!/usr/bin/env python3
"""L4 — GRADE gate: the A->E grade model must be IDENTICAL between the two
implementations (the HTML report JS and the binary's Go). We extract weights,
caps and bands from both sources and compare them numerically.

JS: go/internal/render/assets/app.js  (GW / GCAP / ternary bands)
Go: go/internal/audit/audit.go        (w / cap / band switch)

Output: 0 if the models match, 1 otherwise.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
JS = (ROOT / "go/internal/render/assets/app.js").read_text(encoding="utf-8")
GO = (ROOT / "go/internal/audit/audit.go").read_text(encoding="utf-8")


def nums(s):
    return sorted(int(x) for x in re.findall(r"-?\d+", s))


def js_model():
    gw = re.search(r"var GW=\{([^}]*)\}", JS).group(1)
    # infinite cap (critical): drop it before counting (Infinity has no digit)
    gcap = re.search(r"var GCAP=\{([^}]*)\}", JS).group(1).replace("Infinity", "")
    bands = re.search(r"fin>=(\d+)\?'A':fin>=(\d+)\?'B':fin>=(\d+)\?'C':fin>=(\d+)\?'D'", JS)
    return nums(gw), nums(gcap), nums(" ".join(bands.groups()))


def go_model():
    gw = re.search(r"w := map\[string\]float64\{([^}]*)\}", GO).group(1)
    gcap = (
        re.search(r"cap := map\[string\]float64\{([^}]*)\}", GO).group(1).replace("math.Inf(1)", "")
    )
    bands = re.findall(r"case pts >= (\d+):", GO)
    return nums(gw), nums(gcap), nums(" ".join(bands))


def main():
    jw, jc, jb = js_model()
    gw, gc, gb = go_model()
    ok = True
    for name, j, g in (("weights", jw, gw), ("caps", jc, gc), ("bands", jb, gb)):
        if j == g:
            print(f"  ✓ {name} identical: {g}")
        else:
            print(f"  ✗ {name} diverge — JS {j} vs Go {g}")
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
