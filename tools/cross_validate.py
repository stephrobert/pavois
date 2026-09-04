#!/usr/bin/env python3
"""Cross-validate pavois's CIS coverage against TWO independent authoritative sources, so the
base earns auditor trust rather than echoing a single oracle:

  - SSG / ComplianceAsCode datastream  (ssg-<os>-ds.xml)
  - ansible-lockdown <OS>-CIS          (fetched live via `gh`)

Where both external sources agree on a CIS rule, that's the consensus benchmark; pavois's
coverage of THAT is the credible number. Where they disagree, it's benchmark version/scope drift
(reported, not pavois's fault). ansible-lockdown also covers distros SSG doesn't yet (Debian 13,
Ubuntu 26), so it can validate pavois where SSG is silent.

  tools/cross_validate.py <os>
"""

import json
import re
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
AL_REPO_BY_OS = {
    "debian12": "DEBIAN12-CIS",
    "debian13": "DEBIAN13-CIS",
    "ubuntu2204": "UBUNTU22-CIS",
    "ubuntu2404": "UBUNTU24-CIS",
    "ubuntu2604": "UBUNTU26-CIS",
    "rhel8": "RHEL8-CIS",
    "rhel9": "RHEL9-CIS",
}

if len(sys.argv) != 2 or sys.argv[1] in ("-h", "--help"):
    known = ", ".join(sorted(AL_REPO_BY_OS))
    print(__doc__.strip())
    print(f"\nUsage: tools/cross_validate.py <os>\n  <os> is one of: {known}")
    # No argument is a usage request (exit 0); an unknown OS is an error (exit 2).
    sys.exit(0 if len(sys.argv) != 2 or sys.argv[1] in ("-h", "--help") else 2)

OS = sys.argv[1]
AL_REPO = AL_REPO_BY_OS.get(OS)
if AL_REPO is None and OS not in ("fedora", "rhel10"):
    print(f"unknown OS {OS!r}; known: {', '.join(sorted(AL_REPO_BY_OS))}", file=sys.stderr)
    sys.exit(2)


def ssg_cis():
    # Fixed, read-only locations where the SSG datastreams already live (fetched by fetch
    # tooling, documented in CLAUDE.md); we only read them, never create a temp file here.
    for c in (
        f"/tmp/oscap-analysis/ssg/ssg-{OS}-ds.xml",  # nosec B108
        f"/tmp/oscap-analysis/ssg-{OS}-ds.xml",  # nosec B108
        f"/tmp/ssgwork/ssg-{OS}-ds.xml",  # nosec B108
    ):
        if Path(c).exists():
            xml = Path(c).read_text(encoding="utf-8")
            secs = set(re.findall(r"cisecurity[^>]*>(\d+(?:\.\d+)+)<", xml))
            return {s for s in secs if not any(o != s and o.startswith(s + ".") for o in secs)}
    return set()


def al_cis():
    if not AL_REPO:
        return set()
    out = subprocess.run(
        [
            "gh",
            "api",
            f"repos/ansible-lockdown/{AL_REPO}/contents/defaults/main.yml",
            "--jq",
            ".content",
        ],
        capture_output=True,
        text=True,
    ).stdout.strip()
    if not out:
        return set()
    import base64

    body = base64.b64decode(out).decode("utf-8", "ignore")
    return {
        m.replace("rule_", "").replace("_", ".") for m in re.findall(r"rule_\d+(?:_\d+)+", body)
    }


def pavois_cis():
    ref = yaml.safe_load((ROOT / "docs/reference/pavois-content" / f"{OS}.yml").read_text())[
        "rules"
    ]
    out = set()
    for e in ref.values():
        v = (e.get("norms") or {}).get("cis")
        for x in v if isinstance(v, list) else [v]:
            if x:
                out.add(str(x))
    return out


ssg, al, ck = ssg_cis(), al_cis(), pavois_cis()
consensus = ssg & al  # both external authorities agree
only_ssg, only_al = ssg - al, al - ssg
ck_of_consensus = consensus & ck
union = ssg | al

if "--json" in sys.argv:
    print(
        json.dumps(
            {
                "os": OS,
                "sources": {"ssg": len(ssg), "ansible_lockdown": len(al)},
                "consensus": len(consensus),
                "pavois_covered": len(ck_of_consensus),
                "coverage_pct": round(100 * len(ck_of_consensus) / len(consensus), 1)
                if consensus
                else None,
                "gaps": sorted(consensus - ck, key=lambda s: [int(x) for x in s.split(".")]),
                "suspect_mappings": sorted(ck - union - {""}),
            }
        )
    )
    sys.exit(0)
print(f"CIS cross-validation: {OS}\n")
print(f"  Sources: SSG={len(ssg)}  ansible-lockdown({AL_REPO})={len(al)}")
if not al:
    print("  (ansible-lockdown not reachable; showing SSG only)")
print(f"  Consensus (both agree): {len(consensus)} rules")
if consensus:
    print(
        f"    pavois covers: {len(ck_of_consensus)}/{len(consensus)} "
        f"({round(100 * len(ck_of_consensus) / len(consensus), 1)}%)  "
        "<-- the auditor-credible number"
    )
print(
    f"  Divergence between sources: SSG-only {len(only_ssg)}, AL-only {len(only_al)} "
    f"(benchmark version/scope drift)"
)
gaps = sorted(consensus - ck, key=lambda s: [int(x) for x in s.split(".")])
print(
    f"  pavois gaps vs consensus ({len(gaps)}): "
    + ", ".join(gaps[:30])
    + (" …" if len(gaps) > 30 else "")
)
# rules pavois has that NEITHER source lists -> suspicious mappings to review
suspicious = sorted(
    ck - union - {""},
    key=lambda s: ([int(x) for x in s.split(".")] if re.match(r"^\d", s) else [999]),
)
if suspicious:
    print(
        f"  pavois cis NOT in either source ({len(suspicious)}: verify these): "
        + ", ".join(suspicious[:20])
        + (" …" if len(suspicious) > 20 else "")
    )
