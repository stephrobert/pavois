#!/usr/bin/env python3
"""Cross-validate pavois's NIST and PCI-DSS tags against the canonical framework
requirement sets published by intuitem/ciso-assistant-community.

For each OS reference, every `nist` / `pci-dss` tag is checked against the official
framework's requirement identifiers:
  - NIST: only 800-53-form tags (AC-x) are checked (base control); 800-171 (3.x.y)
    is a different publication and reported separately.
  - PCI-DSS: tags are checked against PCI DSS 4.0; the `Req-` prefix is normalised.
A SUSPECT tag is one absent from the official framework (typo, stale, or a sub-bullet
finer than the framework's nodes).

  tools/validate_mappings.py             # all OS, nist + pci-dss
  tools/validate_mappings.py --norm pci-dss
  tools/validate_mappings.py --suspects  # only print OS/norms that have suspects

Source: intuitem/ciso-assistant-community (frameworks fetched raw). pavois ships nothing
from it; this is offline QA tooling only.
"""
import re
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "docs" / "reference" / "pavois-content"
FW_FILE = {"pci-dss": "pcidss-4_0.yaml", "nist": "nist-sp-800-53-rev5.yaml"}
_FW: dict = {}


def framework(norm: str) -> dict:
    f = FW_FILE[norm]
    if f not in _FW:
        raw = subprocess.run(
            ["curl", "-sL", "-m", "40",
             "https://raw.githubusercontent.com/intuitem/ciso-assistant-community/main/"
             f"backend/library/libraries/{f}"], capture_output=True, text=True).stdout
        d = yaml.safe_load(raw) if raw else {}
        fw = (d.get("objects") or {}).get("framework") or {}
        nodes = fw.get("requirement_nodes") or []
        _FW[f] = {"name": fw.get("name"),
                  "refs": {str(n["ref_id"]).lower() for n in nodes if n.get("ref_id")}}
    return _FW[f]


def normalize(norm: str, tag: str) -> str:
    if norm == "pci-dss":
        return re.sub(r"^req-?", "", tag.strip().lower())
    return re.sub(r"[ (].*", "", tag).strip().lower()          # nist base control


def tags(os_name: str, norm: str) -> set:
    rules = yaml.safe_load((REF / f"{os_name}.yml").read_text())["rules"]
    out = set()
    for e in rules.values():
        v = (e.get("norms") or {}).get(norm)
        for x in (v if isinstance(v, list) else [v]):
            if x:
                out.add(str(x))
    return out


def main() -> int:
    norms = [a for a in sys.argv if a in FW_FILE] or list(FW_FILE)
    only_suspects = "--suspects" in sys.argv
    oses = sorted(p.stem for p in REF.glob("*.yml"))
    total_suspect = 0
    for norm in norms:
        fw = framework(norm)
        if not fw["refs"]:
            print(f"!! could not fetch the {norm} framework"); return 2
        print(f"\n=== {norm} — vs {fw['name']} ({len(fw['refs'])} requirements) ===")
        for os_name in oses:
            raw = tags(os_name, norm)
            if norm == "nist":
                considered = {t for t in raw if re.match(r"^[A-Z]{2}-\d", t)}
                other = len(raw - considered)
            else:
                considered, other = raw, 0
            suspect = sorted(t for t in considered if normalize(norm, t) not in fw["refs"])
            total_suspect += len(suspect)
            if only_suspects and not suspect:
                continue
            extra = f"  (+{other} in 800-171)" if other else ""
            tail = f"  SUSPECT {suspect}" if suspect else ""
            print(f"  {os_name:11} {len(considered):3} tags  {len(considered)-len(suspect):3} valid{extra}{tail}")
    print(f"\nTOTAL suspect tags: {total_suspect}")
    return 1 if total_suspect else 0


if __name__ == "__main__":
    raise SystemExit(main())
