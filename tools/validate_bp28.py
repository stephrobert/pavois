#!/usr/bin/env python3
"""Validate pavois's ANSSI-BP-028 tags against the OFFICIAL v2.0 PDF.

ANSSI publishes BP-028 as a PDF where each recommendation is `Rxx` alone on a line,
followed by a line carrying the hardening levels (M/I/E/...) then the official title.
This tool downloads the official v2.0 document, extracts the R -> title map, and
cross-checks pavois's `bp28:` tags:

  - STALE  : an R-number pavois uses that does NOT exist in v2.0 (a leftover from v1.2)
  - R->title: the authoritative reference table (for filling missing tags by hand)

  tools/validate_bp28.py            # report
  tools/validate_bp28.py --titles   # also dump the full R -> title table

Source: ANSSI BP-028 v2.0 (2022), under Licence Ouverte / Etalab: reuse with attribution.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "docs" / "reference" / "pavois-content"
URL = "https://messervices.cyber.gouv.fr/documents-guides/fr_np_linux_configuration-v2.0.pdf"
# Stable cache files (download once, reuse across runs); honor $TMPDIR rather than hardcode /tmp.
_TMP = Path(tempfile.gettempdir())
PDF = _TMP / "anssi-bp028-v2.pdf"
TXT = _TMP / "anssi-bp028-v2.txt"


def official_map() -> dict[str, str]:
    """R-number -> official title, from the v2.0 PDF."""
    if not PDF.exists():
        subprocess.run(["curl", "-sL", "-m", "60", URL, "-o", str(PDF)], check=True)
    if not TXT.exists() or TXT.stat().st_mtime < PDF.stat().st_mtime:
        subprocess.run(["pdftotext", "-layout", str(PDF), str(TXT)], check=True)
    lines = TXT.read_text(encoding="utf-8", errors="ignore").splitlines()
    out: dict[str, str] = {}
    for i, ln in enumerate(lines):
        if re.fullmatch(r"\s*R\d{1,3}\s*", ln) and i + 1 < len(lines):
            rec = ln.strip()
            title = lines[i + 1]
            # strip leading hardening-level letters (M / I / E / R / ...) and spacing
            title = re.sub(r"^\s*([MIERmie]\s+)+", "", title).strip()
            if title and rec not in out:  # first occurrence = the definition
                out[rec] = title
    return out


def pavois_tags() -> dict[str, list[str]]:
    """R-number -> [control ids] that carry it (union across all OS references)."""
    import yaml

    used: dict[str, list[str]] = {}
    for f in REF.glob("*.yml"):
        rules = yaml.safe_load(f.read_text())["rules"]
        for cid, e in rules.items():
            v = (e.get("norms") or {}).get("bp28")
            for x in v if isinstance(v, list) else [v]:
                if x and re.fullmatch(r"R\d+", str(x)):
                    used.setdefault(str(x), [])
                    if cid not in used[str(x)]:
                        used[str(x)].append(cid)
    return used


def main() -> int:
    off = official_map()
    used = pavois_tags()
    if not off:
        print("!! could not parse the official PDF (R -> title empty)")
        return 2
    print(f"ANSSI BP-028 v2.0: {len(off)} recommendations parsed (R-numbers)")
    print(f"pavois uses {len(used)} distinct R-numbers\n")

    stale = sorted((r for r in used if r not in off), key=lambda r: int(r[1:]))
    if stale:
        print("STALE: R-numbers pavois uses that are ABSENT from v2.0 (likely v1.2 residue):")
        for r in stale:
            print(f"  {r}: {', '.join(used[r][:4])}{' …' if len(used[r]) > 4 else ''}")
    else:
        print("OK: every pavois bp28 tag exists in v2.0.")

    uncovered = sorted((r for r in off if r not in used), key=lambda r: int(r[1:]))
    print(f"\nv2.0 recommendations NOT referenced by any pavois control: {len(uncovered)}")
    print("  (many are organisational/physical and out of scope for a host scanner)")

    if "--titles" in sys.argv:
        print("\nR -> official title (v2.0):")
        for r in sorted(off, key=lambda r: int(r[1:])):
            print(f"  {r}\t{off[r]}")
    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
