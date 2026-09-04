#!/usr/bin/env python3
"""Seed the pavois reference from the committed corpus, losslessly. One control
-> one reference entry holding EVERYTHING needed to build a test (the effective
check) AND a report (standards, levels, title, severity, domain).

This is a one-time SEED: it restructures the corpus (profiles/linux/<os>/controls/
*.rb) into docs/reference/pavois-content/<os>.yml. Afterwards the reference is the
source of truth (render_reference.py renders it back to InSpec), and the datastream
miner is dropped.

Usage: tools/build_reference.py <os>
"""

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
NORMS = ("bp28", "cis", "pci-dss", "nist", "stig")
CTRL_RE = re.compile(r"^control '([^']+)' do\n(.*?)^end", re.S | re.M)
TAG_COLON = re.compile(r"^\s*tag ([a-z0-9_]+): '(.*)'\s*$")
TAG_ARROW = re.compile(r"^\s*tag\('([^']+)' => '(.*)'\)\s*$")


def severity(impact):
    f = float(impact)
    return "critical" if f >= 0.9 else "high" if f >= 0.7 else "medium" if f >= 0.4 else "low"


def parse_control(cid, body):
    lines = body.split("\n")
    impact, title, tags, check = "0.5", cid, {}, []
    for line in lines:
        if not line.strip():
            continue
        if line.strip().startswith("impact "):
            impact = line.split()[1]
        elif re.match(r"\s*title '", line):
            title = re.search(r"title '(.*)'", line).group(1).replace("\\'", "'")
        elif TAG_COLON.match(line):
            k, v = TAG_COLON.match(line).groups()
            tags[k] = v.replace("\\'", "'")
        elif TAG_ARROW.match(line):
            k, v = TAG_ARROW.match(line).groups()
            tags[k] = v.replace("\\'", "'")
        else:
            check.append(line[2:] if line.startswith("  ") else line)
    entry = {
        "domain": tags.pop("domain", ""),
        "title": title,
        "impact": float(impact),
        "severity": severity(impact),
        "norms": {k: tags[k] for k in NORMS if k in tags},
        "levels": {k[len("level_") :]: v for k, v in tags.items() if k.startswith("level_")},
        "check": [c for c in check if c.strip()],
        "ssg": tags.get("ssg", ""),
    }
    if "merge_group" in tags:
        entry["merge_group"] = tags["merge_group"]
    if "posture" in tags:
        entry["posture"] = tags["posture"]
    return entry


def build(os_name):
    ref = {}
    for rb in sorted((ROOT / "profiles" / "linux" / os_name / "controls").glob("*.rb")):
        for m in CTRL_RE.finditer(rb.read_text(encoding="utf-8")):
            ref[m.group(1)] = parse_control(m.group(1), m.group(2))
    return ref


def main(os_name):
    ref = build(os_name)
    out = ROOT / "docs" / "reference" / "pavois-content"
    out.mkdir(parents=True, exist_ok=True)
    dest = out / f"{os_name}.yml"
    dest.write_text(
        f"# pavois compliance content (pavois-owned reference): {os_name}.\n"
        "# Per control: effective check (the test) + "
        "standards/levels/title/severity (the report).\n"
        "# Source of truth: render_reference.py -> InSpec ; future doc API -> /content/<os>.\n"
        + yaml.safe_dump(
            {"os": os_name, "rules": ref},
            sort_keys=True,
            allow_unicode=True,
            default_flow_style=False,
            width=400,
        ),
        encoding="utf-8",
    )
    from collections import Counter

    nc = Counter(n for r in ref.values() for n in r["norms"])
    print(f"{os_name}: {len(ref)} controls -> {dest}  (standards: {dict(nc)})")


if __name__ == "__main__":
    main(sys.argv[1])
