#!/usr/bin/env python3
"""Mine the devsecops-2026 glossary (813 FR YAML terms) into pavois's BILINGUAL glossary
collection. We take the pavois-relevant categories, keep the French definitions as-is, and leave
the English fields empty for a translation pass (hand or workflow) — `en_status: pending`.

  tools/import_glossary.py [category ...]      # default: security-relevant categories

Output: site/src/content/glossary/<slug>.json  (one bilingual entry per term).
"""
import glob
import json
import sys
from pathlib import Path

import yaml

SRC = Path("/home/bob/Projets/devsecops-2026/src/content/glossaryTerms")
OUT = Path(__file__).resolve().parent.parent / "site" / "src" / "content" / "glossary"
# Categories most relevant to a Linux hardening / compliance tool.
DEFAULT_CATS = ["securite", "fondamentaux", "infrastructure", "operations", "reseau"]

cats = set(sys.argv[1:] or DEFAULT_CATS)
OUT.mkdir(parents=True, exist_ok=True)

n = 0
for f in sorted(glob.glob(str(SRC / "*.yaml"))):
    try:
        d = yaml.safe_load(Path(f).read_text(encoding="utf-8"))
    except Exception:
        continue
    if not d or d.get("category") not in cats or not d.get("slug"):
        continue
    entry = {
        "term": d.get("term", d["slug"]),
        "slug": d["slug"],
        "category": d["category"],
        "tags": d.get("tags") or [],
        "aliases": d.get("aliases") or [],
        "related": d.get("relatedTerms") or [],
        "fr": {
            "translation": d.get("traduction") or "",
            "short": d.get("shortDefinition") or "",
            "full": d.get("fullDefinition") or "",
        },
        "en": {"short": "", "full": ""},   # to translate
        "en_status": "pending",
    }
    (OUT / f"{d['slug']}.json").write_text(
        json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    n += 1

print(f"imported {n} terms (categories: {', '.join(sorted(cats))}) -> {OUT}")
