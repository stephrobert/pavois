#!/usr/bin/env python3
"""Every internal link of the built site must land on a page that exists.

The site had 42 dead internal links and nothing could see them:

  - the handbook rewrites root-relative links to the current language, but from a HARD-CODED
    list of prefixes, and `start`, `installation`, `audit`, `blog` and `about` were not in it.
    A chapter linking to `/start/` therefore shipped it unprefixed, and this site has no page
    outside /en/ and /fr/: it 404'd;
  - the glossary entries cross-referenced each other as `/glossary/selinux/`, one page per
    term. That is a design the site deliberately does NOT have (192 terms, ONE page, one anchor
    each), so all 34 of those links pointed at nothing.

Both are the same class as the rest of this repo's bugs: a fact restated in a second place
instead of derived from the first. A checker cannot prevent that, but it makes it impossible
to ship.

Scripts are stripped before checking: a client-side template (`href="/${lang}/rules/${id}/"`)
is not a link, it is the code that builds one. The naive version of this check reported 1687
false positives for exactly that reason.

Usage: tools/check_site_links.py [site/dist]     (exit 1 if any internal link is dead)
"""

import collections
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "site" / "dist"


def main():
    if not DIST.exists():
        sys.exit(f"{DIST} does not exist — run `mise run site:build` first")

    pages = {
        ("/" + str(p.parent.relative_to(DIST)) + "/").replace("/./", "/")
        for p in DIST.rglob("index.html")
    }
    files = {"/" + str(p.relative_to(DIST)) for p in DIST.rglob("*") if p.is_file()}

    dead: collections.Counter = collections.Counter()
    where: dict[str, str] = {}
    for p in DIST.rglob("*.html"):
        if p.name == "404.html":  # its own canonical is /404/, and it is noindex by design
            continue
        html = re.sub(r"<script.*?</script>", "", p.read_text(errors="ignore"), flags=re.S)
        for m in re.finditer(r'href="(/[^"#?]*)', html):
            h = m.group(1)
            if h in files:
                continue
            if (h if h.endswith("/") else h + "/") not in pages:
                dead[h] += 1
                where.setdefault(h, str(p.relative_to(DIST)))

    total = sum(dead.values())
    print(f"internal links: {len(dead)} dead target(s), {total} occurrence(s)")
    for h, n in dead.most_common(20):
        print(f"   {h:<46} {n:>3}x   (e.g. {where[h]})")
    if dead:
        sys.exit(1)
    print("every internal link lands on a page that exists")


if __name__ == "__main__":
    main()
