#!/usr/bin/env python3
"""One-off: convert verbatim checks in docs/reference/rules.yml to `template:` references, but ONLY
when the template round-trips the check EXACTLY (templates.extract guards this). Lossless by
construction — gen:verify must stay 100% after running this.

A shared check -> `template: {name, ...}`. A check keyed @os (per-OS values) -> `template: {@os:
{os: {name, ...}}}` when every OS variant matches the same template. Run once; thereafter author
new controls with `template:` directly.
"""
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import templates

SRC = Path(__file__).resolve().parent.parent / "docs" / "reference" / "rules.yml"


def main():
    lib = yaml.safe_load(SRC.read_text())
    shared = keyed = 0
    for e in lib.values():
        chk = e.get("check")
        if isinstance(chk, list):
            p = templates.extract(chk)
            if p:
                e["template"] = p
                del e["check"]
                shared += 1
        elif isinstance(chk, dict) and "@os" in chk:
            per = {}
            for os, lines in chk["@os"].items():
                p = templates.extract(lines) if isinstance(lines, list) else None
                if not p:
                    per = None
                    break
                per[os] = p
            if per and len({pp["name"] for pp in per.values()}) == 1:
                e["template"] = {"@os": per}
                del e["check"]
                keyed += 1
    SRC.write_text(yaml.safe_dump(lib, sort_keys=True, allow_unicode=True, width=4096))
    print(f"templated: {shared} shared + {keyed} keyed = {shared + keyed} controls "
          f"({100 * (shared + keyed) // len(lib)}% of {len(lib)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
