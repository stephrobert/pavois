#!/usr/bin/env python3
"""DEV resolver: collapse each "one of" group (docs/reference/exclusivity.yml) into ONE
control "<group>-present" that passes if AT LEAST ONE technology is active. It REPLACES
all the group's per-tech controls (the contradictory install/remove/enable/disable set)
so the corpus/scan/report never contradict.

CRITICAL: the single control INHERITS THE UNION of every replaced control's standards
and levels — no norm relationship is lost. The CHECK imposes no technology (any active
one passes); the remediation pre-fills the platform default (Debian->ufw, RHEL->
firewalld; inspired by the sous-chefs `firewall` cookbook) which the admin can change.

Usage: tools/resolve_exclusivity.py [<os> ...]   (default: all)
"""
import re
import sys
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "docs" / "reference" / "pavois-content"
EXCL = ROOT / "docs" / "reference" / "exclusivity.yml"
IMPACT = {"critical": 1.0, "high": 0.7, "medium": 0.5, "low": 0.3}


def rb(s):
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'") + "'"


def family(os_name):
    return "apt" if os_name.startswith(("debian", "ubuntu")) else "rhel"


def choose_remediation(g, os_name):
    # pre-fill the platform default (Debian->ufw, RHEL->firewalld, …) — admin can change it
    return {"resource": "choose",
            "default": (g.get("default") or {}).get(family(os_name), ""),
            "options": g.get("options", {})}


def resolve(os_name, groups):
    p = CONTENT / f"{os_name}.yml"
    lines = p.read_text().splitlines()
    header = "\n".join(l for l in lines[:3] if l.startswith("#")) + "\n"
    doc = yaml.safe_load(p.read_text())
    rules = doc["rules"]

    for gname, g in groups.items():
        present = f"{gname}-present"
        rx = re.compile(g["members"])
        members = [cid for cid in rules if cid != present and rx.match(cid)]
        if not members:
            if present in rules:  # already collapsed — refresh check/remediation from this file
                rules[present]["check"] = [f"describe command({rb(g['check'])}) do",
                                           "  its('stdout.strip') { should eq 'ok' }", "end"]
                rules[present]["remediation"] = choose_remediation(g, os_name)
                rules[present]["title"] = g["title"]
                rules[present]["domain"] = g["domain"]
            continue
        norms, levels, ssgs = {}, {}, []
        for cid in members:
            norms.update(rules[cid].get("norms", {}) or {})   # UNION of standards — keep traceability
            levels.update(rules[cid].get("levels", {}) or {})
            if rules[cid].get("ssg"):
                ssgs.append(rules[cid]["ssg"])
            del rules[cid]
        rules[present] = {
            "domain": g["domain"],
            "title": g["title"],
            "severity": g["severity"],
            "impact": IMPACT[g["severity"]],
            "norms": dict(sorted(norms.items())),
            "levels": dict(sorted(levels.items())),
            "check": [f"describe command({rb(g['check'])}) do",
                      "  its('stdout.strip') { should eq 'ok' }", "end"],
            # no imposed default: the admin picks one of `options` in the plan (`choose:`)
            "remediation": choose_remediation(g, os_name),
            "ssg": present,
            "replaces": sorted(set(ssgs)),  # provenance of the collapsed controls
        }
        print(f"  {os_name}/{gname}: {len(members)} controls -> {present}  (standards {list(norms)})")

    # exclusivity now lives in exclusivity.yml, not on the controls
    for e in rules.values():
        for k in ("choice_group", "choice_tech", "choice_dir"):
            e.pop(k, None)
    doc.pop("choices", None)

    p.write_text(header + yaml.safe_dump(doc, sort_keys=True, allow_unicode=True,
                                         default_flow_style=False, width=400), encoding="utf-8")


def main(args):
    groups = yaml.safe_load(EXCL.read_text())["groups"]
    for os in (args or [p.stem for p in sorted(CONTENT.glob("*.yml"))]):
        resolve(os, groups)


if __name__ == "__main__":
    main(sys.argv[1:])
