#!/usr/bin/env python3
"""L4 — gate NOTE : le modèle de note A→E doit être IDENTIQUE entre les deux
implémentations (le JS du rapport HTML et le Go du binaire). On extrait poids,
plafonds et bandes des deux sources et on compare numériquement.

JS  : go/internal/render/assets/app.js  (GW / GCAP / bandes ternaires)
Go  : go/internal/audit/audit.go        (w / cap / switch des bandes)

Sortie : 0 si les modèles coïncident, 1 sinon.
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
    # plafond infini (critique) : on le retire avant comptage (Infinity n'a pas de chiffre)
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
    for name, j, g in (("poids", jw, gw), ("plafonds", jc, gc), ("bandes", jb, gb)):
        if j == g:
            print(f"  ✓ {name} identiques : {g}")
        else:
            print(f"  ✗ {name} divergents — JS {j} vs Go {g}")
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
