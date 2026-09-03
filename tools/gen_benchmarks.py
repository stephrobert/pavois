#!/usr/bin/env python3
"""Emit site/src/data/benchmarks.json: the CIS benchmark version Pavois targets, PER OS.

The site claimed "the benchmark version is shown on every rule page" and showed a range
("1.0.0-4.0.0"), which tells a reader nothing. Worse, three OSes have NO CIS benchmark at
all (Fedora, Ubuntu 26.04, RHEL 10): their CIS numbers are INHERITED from a sibling OS.
That is defensible, and hiding it is not. This generator carries the caveat from
docs/reference/norms.yml to the site so the table cannot drift from the source.

Run: mise run gen:benchmarks (part of gen:pages)
"""

import json
import pathlib

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
NORMS = ROOT / "docs" / "reference" / "norms.yml"
OUT = ROOT / "site" / "src" / "data" / "benchmarks.json"

LABEL = {
    "debian12": "Debian 12",
    "debian13": "Debian 13",
    "ubuntu2204": "Ubuntu 22.04",
    "ubuntu2404": "Ubuntu 24.04",
    "ubuntu2604": "Ubuntu 26.04",
    "rhel8": "RHEL 8",
    "rhel9": "RHEL 9",
    "rhel10": "RHEL 10",
    "fedora": "Fedora",
}


def main() -> None:
    norms = yaml.safe_load(NORMS.read_text())
    bv = norms["standards"]["cis"]["benchmark_version"]

    rows = []
    for os_id, entry in bv.items():
        rows.append(
            {
                "os": os_id,
                "label": LABEL.get(os_id, os_id),
                "version": entry.get("version"),
                "source": str(entry.get("source", "")),
                "inherited_from": entry.get("inherited_from"),
                "inherited_label": LABEL.get(entry.get("inherited_from", ""), ""),
            }
        )
    rows.sort(key=lambda r: r["os"])

    OUT.write_text(json.dumps({"cis": rows}, ensure_ascii=False, indent=2) + "\n")
    pinned = sum(1 for r in rows if r["version"])
    print(
        f"benchmarks.json: {len(rows)} OS ({pinned} pinned to a published CIS benchmark, "
        f"{len(rows) - pinned} inherited)"
    )


if __name__ == "__main__":
    main()
