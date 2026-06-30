#!/usr/bin/env python3
"""Find the coverage gap between Pavois and the SCAP Security Guide (SSG / OpenSCAP).

Every Pavois control carries an `ssg:` reference (the SSG rule short id). This tool lists
the SSG rules that NO Pavois control maps yet, optionally scoped to one SSG profile and/or
severity, and can open one GitHub issue per gap so the backlog of controls-to-implement is
populated straight from the authoritative SSG datastream.

Usage:
  coverage_gap.py --os debian12 --datastream ssg-debian12-ds.xml          # report (default)
  coverage_gap.py --os debian12 --datastream ... --severity high          # only high-sev gaps
  coverage_gap.py --os debian12 --datastream ... --profile <ssg-profile>  # only a profile's rules
  coverage_gap.py --os debian12 --datastream ... --create-issues --limit 25
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET  # nosec B405 - trusted local SSG datastream
from pathlib import Path

import yaml

PREFIX = "xccdf_org.ssgproject.content_rule_"
PROFILE_PREFIX = "xccdf_org.ssgproject.content_profile_"


def localname(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def covered_ssg_ids(rules_yml: Path, os_name: str) -> set[str]:
    """SSG short ids already mapped by a Pavois control applicable to this OS."""
    doc = yaml.safe_load(rules_yml.read_text(encoding="utf-8"))
    rules = doc.get("rules", doc)
    out: set[str] = set()
    for ctl in rules.values():
        if not isinstance(ctl, dict):
            continue
        if os_name in (ctl.get("applicable_os") or []) and ctl.get("ssg"):
            out.add(str(ctl["ssg"]))
    return out


def ssg_rules(ds: Path, profile: str | None) -> dict[str, dict]:
    """All SSG rules in the datastream: short id -> {title, severity}. If a profile is
    given, restrict to the rules it selects (select idref=... selected=true)."""
    tree = ET.parse(ds)  # nosec B314 # noqa: S314 - trusted local SSG datastream
    root = tree.getroot()
    rules: dict[str, dict] = {}
    for el in root.iter():
        if localname(el.tag) != "Rule":
            continue
        rid = el.get("id", "")
        short = rid[len(PREFIX) :] if rid.startswith(PREFIX) else rid
        title = ""
        for child in el:
            if localname(child.tag) == "title":
                title = "".join(child.itertext()).strip()
                break
        rules[short] = {"title": title, "severity": el.get("severity", "unknown")}
    if not profile:
        return rules
    pid = profile if profile.startswith(PROFILE_PREFIX) else PROFILE_PREFIX + profile
    selected: set[str] = set()
    for el in root.iter():
        if localname(el.tag) == "Profile" and el.get("id") == pid:
            for child in el:
                if localname(child.tag) == "select" and child.get("selected") == "true":
                    idref = child.get("idref", "")
                    selected.add(idref[len(PREFIX) :] if idref.startswith(PREFIX) else idref)
    return {k: v for k, v in rules.items() if k in selected}


def oscap_verdicts(path: Path) -> dict[str, str]:
    """Map SSG short id -> oscap result (pass/fail/notapplicable/notchecked/...), from an
    `oscap xccdf eval --results` XML. This is the authoritative applicability call: a rule
    oscap marks `notapplicable` on the real target is NOT a coverage gap (e.g. SELinux rules
    on an AppArmor distro). Used to triage the raw gap down to the real, actionable one."""
    tree = ET.parse(path)  # nosec B314 # noqa: S314 - trusted local oscap results
    out: dict[str, str] = {}
    for el in tree.getroot().iter():
        if localname(el.tag) != "rule-result":
            continue
        idref = el.get("idref", "")
        short = idref[len(PREFIX) :] if idref.startswith(PREFIX) else idref
        for child in el:
            if localname(child.tag) == "result":
                out[short] = (child.text or "").strip()
                break
    return out


ERROR_MARKERS = re.compile(
    r"NoMethodError|undefined method|uninitialized constant|unexpected error|Errno::|"
    r"NameError|ArgumentError|TypeError|backtrace|raised|exit status [1-9]",
    re.IGNORECASE,
)


def broken_controls(report: Path) -> list[dict]:
    """Pavois controls that DON'T WORK: a scan result carrying a Ruby exception / error
    marker (a broken matcher or resource), not a legitimate compliance failure. These are
    bugs in the control, distinct from coverage gaps. Returns [{id, title, msg}]."""
    doc = json.loads(report.read_text(encoding="utf-8"))
    out: list[dict] = []
    for prof in doc.get("profiles", []):
        for ctl in prof.get("controls", []):
            for r in ctl.get("results", []):
                msg = " ".join(
                    filter(None, (r.get("message"), r.get("code_desc"), r.get("skip_message")))
                )
                if ERROR_MARKERS.search(msg):
                    out.append(
                        {
                            "id": ctl.get("id", "?"),
                            "title": ctl.get("title", ""),
                            "msg": msg.strip()[:300],
                        }
                    )
                    break
    return out


def existing_issue_titles() -> set[str]:
    try:
        out = subprocess.run(  # noqa: S603
            ["gh", "issue", "list", "--state", "all", "--limit", "1000", "--json", "title"],
            capture_output=True,
            text=True,
            check=True,
        )
        return {i["title"] for i in json.loads(out.stdout or "[]")}
    except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError):
        return set()


def create_issue(title: str, body: str, label: str) -> bool:
    try:
        subprocess.run(  # noqa: S603
            ["gh", "issue", "create", "--title", title, "--body", body, "--label", label],
            capture_output=True,
            text=True,
            check=True,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def main() -> int:
    ap = argparse.ArgumentParser(description="Pavois vs SSG/OpenSCAP coverage gap")
    ap.add_argument("--os", default="debian12")
    ap.add_argument("--datastream", required=True, type=Path)
    ap.add_argument("--rules", type=Path, default=Path("docs/reference/rules.yml"))
    ap.add_argument("--profile", default=None, help="restrict to one SSG profile id (or suffix)")
    ap.add_argument("--severity", default=None, choices=["high", "medium", "low", "unknown"])
    ap.add_argument(
        "--oscap-results",
        type=Path,
        default=None,
        help="oscap results XML; triages out N/A rules, keeps only the real applicable gap",
    )
    ap.add_argument(
        "--pavois-report",
        type=Path,
        default=None,
        help="a pavois scan JSON; broken controls (errors/exceptions) become `bug` issues",
    )
    ap.add_argument("--format", default="md", choices=["md", "json", "csv"])
    ap.add_argument("--create-issues", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="cap issues created (0 = no cap)")
    ap.add_argument("--label", default="coverage-gap")
    args = ap.parse_args()

    covered = covered_ssg_ids(args.rules, args.os)
    rules = ssg_rules(args.datastream, args.profile)
    gap = {k: v for k, v in rules.items() if k not in covered}
    if args.severity:
        gap = {k: v for k, v in gap.items() if v["severity"] == args.severity}

    # Triage with oscap's own verdicts: a rule oscap marks notapplicable on the real target
    # is NOT a gap (e.g. SELinux on an AppArmor distro). Only applicable rules count, and the
    # FAILING ones are the priority backlog. Without results, the raw gap is N/A-inflated.
    verdicts = oscap_verdicts(args.oscap_results) if args.oscap_results else {}
    applicable_states = {"fail", "pass", "error"}
    triage = {"applicable": 0, "fail": 0, "notapplicable": 0, "notchecked": 0}
    for short, v in gap.items():
        r = verdicts.get(short, "")
        v["verdict"] = r
        if not verdicts:
            continue
        if r in applicable_states:
            triage["applicable"] += 1
            triage["fail"] += r == "fail"
        elif r == "notapplicable":
            triage["notapplicable"] += 1
        else:
            triage["notchecked"] += 1

    order = {"high": 0, "medium": 1, "low": 2, "unknown": 3}
    items = sorted(gap.items(), key=lambda kv: (order.get(kv[1]["severity"], 9), kv[0]))
    by_sev: dict[str, int] = {}
    for _, v in items:
        by_sev[v["severity"]] = by_sev.get(v["severity"], 0) + 1

    if args.create_issues:
        existing = existing_issue_titles()
        # Bugs first: broken pavois controls (errors), independent of the coverage triage.
        if args.pavois_report:
            made_b = 0
            for b in broken_controls(args.pavois_report):
                title = f"bug: control {b['id']} errors during scan"
                if title in existing:
                    continue
                body = (
                    f"The control **`{b['id']}`** raised an error during a scan, this is a broken "
                    f"control (a bad matcher/resource), not a compliance failure:\n\n"
                    f"```\n{b['msg']}\n```\n\n> {b['title']}\n\n"
                    f"Fix the control so it evaluates cleanly, then re-scan."
                )
                if create_issue(title, body, "bug"):
                    made_b += 1
                    print(f"  bug: {title}")
            print(f"created {made_b} bug issue(s) (label: bug)")
        # Coverage gaps need the oscap triage, else the raw gap is N/A-inflated.
        if not verdicts:
            print(
                "note: skipping coverage issues without --oscap-results (raw gap includes N/A).",
                file=sys.stderr,
            )
            return 0
        made = 0
        for short, v in items:
            if v["verdict"] != "fail":  # only real, applicable, failing gaps
                continue
            if args.limit and made >= args.limit:
                break
            title = f"coverage: implement SSG rule {short} ({v['severity']})"
            if title in existing:
                continue
            body = (
                f"Pavois has no control mapping the SSG rule **`{short}`** "
                f"(severity: {v['severity']}) for {args.os}. oscap evaluates it as **fail** on a "
                f"real target, so it is applicable and currently non-compliant.\n\n"
                f"> {v['title']}\n\n"
                f"Implement a control (effective-config where the rule is service-resolved), "
                f"tag it `ssg: {short}`, map the standards it belongs to, and re-run "
                f"`tools/coverage_gap.py` to confirm it closes.\n\n"
                f"_Generated from {args.datastream.name}._"
            )
            if create_issue(title, body, args.label):
                made += 1
                print(f"  issue: {title}")
        print(f"\ncreated {made} issue(s) (label: {args.label})")
        return 0

    if args.format == "json":
        print(
            json.dumps(
                {
                    "os": args.os,
                    "covered": len(covered),
                    "ssg_total": len(rules),
                    "gap_raw": len(gap),
                    "by_severity": by_sev,
                    "triage": triage if verdicts else None,
                    "rules": [{"id": k, **v} for k, v in items],
                },
                indent=2,
            )
        )
        return 0

    if args.format == "csv":
        # Workflow-ready backlog: auto triage from oscap + empty manual columns so each
        # applicable-failing row can become an issue without manual investigation.
        def _triage(r: str) -> str:
            if r in ("fail", "error"):
                return "backlog"
            if r == "pass":
                return "already-pass"
            if r == "notapplicable":
                return "n/a"
            return "notchecked" if r == "" or r == "notchecked" else r

        w = csv.writer(sys.stdout)
        w.writerow(
            [
                "severity",
                "ssg_rule",
                "title",
                "oscap_verdict",
                "triage",
                "pavois_equivalent",
                "decision",
                "reason",
                "issue_url",
                "owner",
                "status",
            ]
        )
        for short, v in items:
            tr = _triage(v["verdict"]) if verdicts else ""
            w.writerow(
                [
                    v["severity"],
                    short,
                    v["title"],
                    v["verdict"] or "",
                    tr,
                    "",
                    "",
                    "",
                    "",
                    "",
                    "todo" if tr == "backlog" else "",
                ]
            )
        return 0

    scope = f" (profile {args.profile})" if args.profile else ""
    print(f"# Pavois vs SSG coverage gap — {args.os}{scope}\n")
    if verdicts:
        print(
            f"Raw gap {len(gap)} SSG rules, but triaged by oscap on a real target: "
            f"**{triage['fail']} applicable & failing** (the real backlog), "
            f"{triage['applicable'] - triage['fail']} applicable & already passing, "
            f"{triage['notapplicable']} N/A, {triage['notchecked']} not auto-checked. "
            f"Only the applicable-failing rules are issue-worthy.\n"
        )
    else:
        print(
            f"Pavois maps {len(covered)} SSG ids; the datastream has {len(rules)} rules; "
            f"**{len(gap)} not covered** ({by_sev}). Pass --oscap-results to triage out N/A.\n"
        )
    print("| Severity | oscap | SSG rule | Title |")
    print("|---|---|---|---|")
    for short, v in items:
        print(f"| {v['severity']} | {v['verdict'] or '?'} | `{short}` | {v['title']} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
