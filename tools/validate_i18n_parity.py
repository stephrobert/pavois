#!/usr/bin/env python3
"""Validate FR/EN structural parity of the bilingual site content.

The two languages are never byte-identical (different prose), but they must be
STRUCTURALLY equivalent: both languages present, and the same number of H2
sections, FAQ pairs, code fences and links. A mismatch means a translation
drifted (a section added in one language only, a FAQ left untranslated, a broken
link in one locale). Exit non-zero if any file is out of parity.

Usage: python3 tools/validate_i18n_parity.py [content-dir ...]
Default dir: site/src/content/handbook
"""

import json
import re
import sys
from pathlib import Path

H2 = re.compile(r"^##\s+\S", re.M)
FENCE = re.compile(r"^```", re.M)
# A FAQ pair is a block that starts with **Question…** (bold lead-in).
FAQ = re.compile(r"^\*\*[^*].*?\*\*", re.M)
LINK = re.compile(r"\]\(")


def faq_count(md: str) -> int:
    # Count FAQ pairs only inside the `## FAQ` section, so bold terms elsewhere in
    # the body (which legitimately differ between languages) are not counted.
    parts = re.split(r"^##\s+FAQ\s*$", md, flags=re.M)
    if len(parts) < 2:
        return 0
    section = re.split(r"^##\s", parts[1], flags=re.M)[0]
    return len(FAQ.findall(section))


def metrics(md: str) -> dict:
    return {
        "h2": len(H2.findall(md)),
        "fences": len(FENCE.findall(md)),
        "faq": faq_count(md),
        "links": len(LINK.findall(md)),
    }


def check_file(path: Path) -> list[str]:
    d = json.loads(path.read_text(encoding="utf-8"))
    body = d.get("body")
    problems = []
    # every bilingual string field must have both locales
    for field in ("title", "summary", "body"):
        v = d.get(field)
        if isinstance(v, dict):
            for lang in ("en", "fr"):
                if not v.get(lang):
                    problems.append(f"{field}: missing '{lang}'")
    if not isinstance(body, dict) or not body.get("en") or not body.get("fr"):
        return problems
    me, mf = metrics(body["en"]), metrics(body["fr"])
    for k in me:
        if me[k] != mf[k]:
            problems.append(f"body.{k}: en={me[k]} fr={mf[k]}")
    return problems


def main() -> int:
    dirs = sys.argv[1:] or ["site/src/content/handbook"]
    files = sorted(p for d in dirs for p in Path(d).glob("*.json"))
    if not files:
        print("no content files found", file=sys.stderr)
        return 1
    bad = 0
    for p in files:
        probs = check_file(p)
        if probs:
            bad += 1
            print(f"✗ {p.name}")
            for pr in probs:
                print(f"    {pr}")
    if bad:
        print(f"\n{bad}/{len(files)} file(s) out of FR/EN parity")
        return 1
    print(f"✓ {len(files)} file(s) in FR/EN parity")
    return 0


if __name__ == "__main__":
    sys.exit(main())
