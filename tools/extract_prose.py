#!/usr/bin/env python3
"""One-off migration: pull the AUTHORED prose out of the generated rule fiches.

site/src/content/rules/<id>.json was a hybrid: technical fields DERIVED from rules.yml (check,
remediation, norms, supported_os, severity…) sitting in the same file as bilingual prose WRITTEN BY
HAND (title, summary, rationale, check_note, verify, logs, remediation_note, impact). The generator
had to read its own output back to avoid destroying the prose, the fiches had to be versioned even
though most of their content was derived, and every rule change churned 789 files in the diff.

Splitting them puts each thing where it belongs:

  docs/reference/rules.yml        the rules            (source, versioned)
  docs/reference/prose/<id>.json  the prose about them (source, versioned, NEXT TO the rules)
  site/src/content/rules/<id>.json  100% derived       (generated at build, gitignored)

The site then consumes an artifact instead of being one, which is also the only way a separate site
repository could ever work without re-opening the drift this repo just closed.

Usage: tools/extract_prose.py [--apply]
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FICHES = ROOT / "site" / "src" / "content" / "rules"
PROSE = ROOT / "docs" / "reference" / "prose"

# What a human writes. Everything else in a fiche comes from rules.yml and is regenerated.
AUTHORED = (
    "title",
    "summary",
    "rationale",
    "check_note",
    "verify",
    "logs",
    "remediation_note",
    "impact",
    "datePublished",  # editorial dates: when the PAGE was first published / last rewritten
    "dateModified",
)


def main():
    apply = "--apply" in sys.argv
    n = fields = 0
    if apply:
        PROSE.mkdir(parents=True, exist_ok=True)
    for f in sorted(FICHES.glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        out = {k: d[k] for k in AUTHORED if k in d}
        if not out:
            continue
        out = {"id": d["id"], **out}
        fields += len(out) - 1
        n += 1
        if apply:
            (PROSE / f.name).write_text(
                json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
    print(f"{n} prose file(s), {fields} authored field(s) extracted to docs/reference/prose/")
    if not apply:
        print("(dry-run: pass --apply)")


if __name__ == "__main__":
    main()
