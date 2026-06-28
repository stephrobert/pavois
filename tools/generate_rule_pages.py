#!/usr/bin/env python3
"""Populate the Astro site with ONE content entry per rule (by neutral control id), not per OS —
a pavois control is OS-neutral by design. Each fiche lists the OSes that support it and the CIS
benchmark version per OS. Data (check, remediation, rationale) is shared across OSes; norm mappings
are merged (union). Uses the norm-studio's draft_rule_page (mines reference + SSG, no LLM).

  tools/generate_rule_pages.py            # all OS references -> one fiche per unique id

Wipes and regenerates site/src/content/rules/ (then the gold hand-authored fiches are re-applied
separately). FR fields echo EN until a translation pass.
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent / "norm_studio"))
import server  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "docs" / "reference" / "pavois-content"
OUT = ROOT / "site" / "src" / "content" / "rules"
OUT.mkdir(parents=True, exist_ok=True)

# Remove stale per-OS entries (old model); keep per-id fiches (they may be enriched).
for f in OUT.glob("*--*.json"):
    f.unlink()

RICH = ("summary", "check_note", "verify", "logs", "remediation_note", "impact")


def _is_enriched(path: Path) -> bool:
    try:
        d = json.loads(path.read_text(encoding="utf-8"))
        return any(k in d for k in RICH)
    except Exception:
        return False

oses = sorted(p.stem for p in REF.glob("*.yml"))
print(f"OSes: {', '.join(oses)}", flush=True)
by_id: dict[str, list] = defaultdict(list)
for os_name in oses:
    rules = yaml.safe_load((REF / f"{os_name}.yml").read_text())["rules"]
    print(f"  {os_name}: {len(rules)} rules…", flush=True)
    for rid in rules:
        try:
            d = server._draft_rule_page(os_name, rid)
        except Exception:
            continue
        if "error" not in d:
            # the server draft drops/mis-defaults these; carry them straight from the authoritative OS file
            d["evidence_type"] = rules[rid].get("evidence_type")
            d["reboot_survivable"] = rules[rid].get("reboot_survivable")
            d["severity"] = rules[rid].get("severity")
            by_id[rid].append((os_name, d))

_SEV_RANK = {"low": 1, "medium": 2, "high": 3, "critical": 4}


def _max_sev(items):
    """Most severe rating across the OSes that carry this control (severity can vary @os)."""
    sevs = [d.get("severity") for _, d in items if d.get("severity") in _SEV_RANK]
    return max(sevs, key=lambda s: _SEV_RANK[s]) if sevs else "unknown"


gen = kept = 0
for rid, items in sorted(by_id.items()):
    items.sort(key=lambda x: x[0])
    base = items[0][1]
    supported = [o for o, _ in items]
    merged: dict[str, list] = {}
    os_versions: dict[str, str] = {}
    for os_name, d in items:
        for k, v in (d.get("norms") or {}).items():
            vals = v if isinstance(v, list) else [v]
            merged.setdefault(k, [])
            for x in vals:
                if x is not None and str(x) not in [str(y) for y in merged[k]]:
                    merged[k].append(x)
        cis = (d.get("norm_versions") or {}).get("cis")
        if cis:
            os_versions[os_name] = cis
    norms = {k: (v[0] if len(v) == 1 else v) for k, v in merged.items() if v}

    entry = {
        "id": rid,
        "supported_os": supported,
        "os_versions": os_versions,
        "severity": _max_sev(items),
        "domain": base.get("domain"),
        "evidence_type": base.get("evidence_type"),
        "reboot_survivable": base.get("reboot_survivable"),
        "norms": norms,
        "check": base.get("check", []),
        "remediation": base.get("remediation", {}),
        "title": base["title"],
        "needs_translation": base.get("needs_translation", ["title.fr"]),
    }
    if base.get("rationale"):
        entry["rationale"] = base["rationale"]
    out = OUT / f"{rid}.json"
    if out.exists():                       # refresh technical fields, PRESERVE authored bilingual prose
        try:
            ex = json.loads(out.read_text(encoding="utf-8"))
            for k in ("title", "summary", "rationale", "check_note", "verify", "logs",
                      "remediation_note", "impact", "needs_translation",
                      "datePublished", "dateModified"):  # hand-maintained editorial dates
                if k in ex:
                    entry[k] = ex[k]
            if _is_enriched(out):
                kept += 1
        except Exception:
            pass
    out.write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    gen += 1

print(f"wrote {gen} fiches ({kept} kept their authored prose), from {len(oses)} OSes")
