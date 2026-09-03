#!/usr/bin/env python3
"""The site is a DERIVED artifact. Prove it, or fail.

site/src/content/rules/ holds one fiche per control and is VERSIONED, but it is produced by
tools/generate_rule_pages.py — a script that, until now, no task ever ran. So the site drifted from
the rule base and nothing could say so: 19 controls the scanner runs had no page (including the
whole `growth-*` family and the journald forwarding control written the same day), 17 fiches
documented controls that had been deleted, and Ubuntu 26.04 — 652 controls in the reference —
appeared on exactly zero pages, while the home page counted "8 Linux targets".

`gen:verify` gives the InSpec corpus that guarantee ("5919/5919 controls in sync"). This is the
same guarantee for the site.

Usage: tools/verify_site_content.py       (exit 1 on any drift)
"""

import glob
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "docs" / "reference" / "rules.yml"
REF = ROOT / "docs" / "reference" / "pavois-content"
FICHES = ROOT / "site" / "src" / "content" / "rules"
PROSE = ROOT / "docs" / "reference" / "prose"


def main():
    src = yaml.safe_load(RULES.read_text(encoding="utf-8"))
    live = {k: v for k, v in src.items() if isinstance(v, dict) and "applicable_os" in v}

    # A control no OS runs is dead weight in the source, and it is why 5 ids have no fiche: say so
    # here rather than let it look like the site is missing pages.
    dead = sorted(k for k, v in live.items() if not v.get("applicable_os"))
    expected = {k for k in live if live[k].get("applicable_os")}

    # The fiches are now GENERATED (site/src/content/rules/ is rebuilt from scratch and gitignored),
    # so comparing them to the rule base would always pass: the generator makes them agree. What can
    # actually drift is the SOURCE that feeds them, the authored prose, so that is what we check.
    have = {
        Path(p).stem: json.loads(Path(p).read_text(encoding="utf-8"))
        for p in glob.glob(str(FICHES / "*.json"))
    }
    prose = {Path(p).stem for p in glob.glob(str(PROSE / "*.json"))}
    no_prose = sorted(expected - prose)
    orphan_prose = sorted(prose - expected)

    missing = sorted(expected - set(have))
    stale = sorted(set(have) - expected)

    # every OS of the reference must appear on at least one fiche, or a whole target is invisible
    oses = sorted(p.stem for p in REF.glob("*.yml"))
    covered = {o for f in have.values() for o in f.get("supported_os", [])}
    uncovered = sorted(set(oses) - covered)

    todo = sorted(k for k, f in have.items() if f.get("needs_authoring"))
    untranslated = sorted(k for k, f in have.items() if f.get("needs_translation"))

    print(f"source: {len(expected)} live controls ({len(dead)} dead: applicable_os is empty)")
    print(f"site  : {len(have)} fiches, covering {len(covered)}/{len(oses)} OSes")
    fail = 0
    for label, items in (
        ("MISSING (the scanner runs it, the site does not document it)", missing),
        ("STALE (a page for a control that no longer exists)", stale),
        ("UNCOVERED OS (a whole target invisible on the site)", uncovered),
        ("NO PROSE (a control nobody has written a word about)", no_prose),
        ("ORPHAN PROSE (prose about a control that no longer exists)", orphan_prose),
    ):
        if items:
            fail += len(items)
            print(f"\n{label}: {len(items)}")
            for i in items[:15]:
                print(f"   {i}")
            if len(items) > 15:
                print(f"   ... and {len(items) - 15} more")

    if dead:
        print(f"\ndead controls in rules.yml (no OS runs them — remove or scope them): {len(dead)}")
        for d in dead:
            print(f"   {d}")
    # editorial debt: reported, never fatal — it is work to do, not a broken build
    print(
        f"\neditorial debt: {len(todo)} fiche(s) need authored prose, "
        f"{len(untranslated)} need a FR pass"
    )

    if fail:
        print(f"\nDRIFT: {fail} problem(s) — run `mise run gen:pages` to rebuild the site content")
        sys.exit(1)
    print("\nthe site content is in sync with the rule base")


if __name__ == "__main__":
    main()
