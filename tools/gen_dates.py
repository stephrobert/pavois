#!/usr/bin/env python3
"""Give every rule fiche a real datePublished / dateModified, taken from git.

Not one of the 789 fiches carried a date, so ~1578 TechArticle blocks were emitted with no
datePublished (Google's Rich Results Test flags it), and the sitemap emitted no `lastmod` at all —
the condition `iso(dateModified ?? datePublished)` was always undefined, so a crawler had no way to
know what had changed.

The honest source is the repository itself: when the fiche first appeared, and when it last changed.
Inventing a date, or stamping the build date on 789 pages, would be worse than none (it tells a
crawler everything changed, every build).

Dates are written INTO the fiches, and tools/generate_rule_pages.py already preserves them across a
regeneration, so this runs when you want to refresh them, not on every build.

Usage: tools/gen_dates.py [--check]     (--check: exit 1 if a fiche has no date)
"""

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# The AUTHORED sources, not the generated fiches: site/src/content/rules/ is rebuilt from scratch on
# every build and has no history of its own. A page's dates are the history of the prose that IS the
# page (docs/reference/prose/), and of the handbook chapter. tools/generate_rule_pages.py then
# carries them into the fiche it emits.
DIRS = ("docs/reference/prose", "site/src/content/handbook")


def git_dates(rel: str) -> dict[str, tuple[str, str]]:
    """{entry stem: (first commit date, last commit date)} in one pass over the history."""
    out = subprocess.run(
        ["git", "log", "--reverse", "--date=short", "--format=@%ad", "--name-only", "--", rel],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    first: dict[str, str] = {}
    last: dict[str, str] = {}
    date = ""
    for line in out.splitlines():
        if line.startswith("@"):
            date = line[1:]
        elif line.startswith(rel) and line.endswith(".json"):
            stem = Path(line).stem
            first.setdefault(stem, date)
            last[stem] = date
    return {k: (first[k], last[k]) for k in first}


def main():
    check = "--check" in sys.argv
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    stamped = new = missing = total = 0

    for rel in DIRS:
        dates = git_dates(rel)
        for p in sorted((ROOT / rel).glob("*.json")):
            total += 1
            d = json.loads(p.read_text(encoding="utf-8"))
            pub, mod = dates.get(p.stem, (None, None))
            if pub is None:  # never committed yet: it is born today, and that is true
                pub = mod = today
                new += 1
            if check:
                if not d.get("datePublished"):
                    missing += 1
                continue
            # datePublished is EDITORIAL data: when the page first went out. It is never rewritten
            # (a file that has no git history yet is not a page that was published today, it is a
            # page whose history has not been committed yet).
            pub = d.get("datePublished") or pub
            if d.get("datePublished") != pub or d.get("dateModified") != mod:
                d["datePublished"] = pub
                d["dateModified"] = mod
                p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                stamped += 1

    if check:
        print(f"{missing}/{total} entries without a date")
        sys.exit(1 if missing else 0)
    print(f"stamped {stamped}/{total} entries from git history ({new} new, dated today)")


if __name__ == "__main__":
    main()
