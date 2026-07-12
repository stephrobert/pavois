#!/usr/bin/env python3
"""Per-OS scan-result baseline + regression detector.

Keeps the BEST-known scan result per OS in docs/reference/baselines/<os>.json (the set of
passing control ids, + optional lynis index). A regression test re-scans the OS and compares:

  REGRESSION = a control that PASSED in the baseline but now FAILS   -> exit 1 (CI-friendly)
  FIX        = a control that FAILED in the baseline but now PASSES
  lynis drop = current lynis index below the baseline's

`--update` promotes the current result to the baseline ONLY when it is at least as good
(no regressions and >= passing count): the baseline always holds the best result seen.

This is what caught the -pavhardened Debian kernel stranding nftables (firewall controls
flipped pass->fail): a stored baseline makes such regressions obvious instead of manual.

Usage:
  # after a scan, seed/refresh the baseline (best result):
  python3 tools/regression.py <scan.json> --os debian12 --lynis 90 --update
  # later, on a suspected-regression scan, compare (non-zero exit if regressed):
  python3 tools/regression.py <scan.json> --os debian12 --lynis 88
"""

import argparse
import datetime
import json
import os
import sys

BASELINE_DIR = "docs/reference/baselines"


def extract(scan_path):
    """passing/failing control-id sets from a pavois (InSpec) scan JSON."""
    with open(scan_path) as f:
        d = json.load(f)
    passing, failing = set(), set()
    for prof in d.get("profiles", []):
        for c in prof.get("controls", []):
            cid = c.get("id")
            results = c.get("results", [])
            if not cid or not results:  # no assertion ran (n/a / skipped) -> neither
                continue
            (failing if any(r.get("status") == "failed" for r in results) else passing).add(cid)
    return passing, failing


def save(bpath, a, passing, failing):
    os.makedirs(BASELINE_DIR, exist_ok=True)
    data = {
        "os": a.os,
        "updated": datetime.date.today().isoformat(),
        "label": a.label,
        "lynis": a.lynis,
        "n_pass": len(passing),
        "n_fail": len(failing),
        "passing": sorted(passing),
        "failing": sorted(failing),
    }
    with open(bpath, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scan", help="pavois scan JSON")
    ap.add_argument("--os", required=True)
    ap.add_argument("--update", action="store_true", help="promote to baseline if >= best")
    ap.add_argument("--lynis", type=int, default=None, help="lynis hardening index for this scan")
    ap.add_argument("--label", default="")
    # A baseline is only a reference while the CORPUS is the same. After a campaign that
    # merges duplicates and drops controls that could never pass, "fewer passing" is not a
    # regression, it is a smaller (and honest) denominator. --reset re-anchors it, and the
    # label must say why: a baseline nobody can explain is not opposable.
    ap.add_argument(
        "--reset",
        action="store_true",
        help="re-anchor the baseline (the corpus changed); --label is then required",
    )
    a = ap.parse_args()

    passing, failing = extract(a.scan)
    bpath = os.path.join(BASELINE_DIR, a.os + ".json")

    if not os.path.exists(bpath):
        print(
            f"[{a.os}] no baseline yet: {len(passing)} passing, {len(failing)} failing"
            + (f", lynis {a.lynis}" if a.lynis is not None else "")
        )
        if a.update or a.reset:  # --reset anchors a FIRST baseline too, not only a re-anchor
            save(bpath, a, passing, failing)
            print(f"  -> baseline created at {bpath}")
        return 0

    with open(bpath) as f:
        b = json.load(f)
    base_pass, base_fail = set(b["passing"]), set(b.get("failing", []))
    regressions = sorted(base_pass & failing)
    fixes = sorted(base_fail & passing)

    print(
        f"=== regression check: {a.os} (baseline {b.get('updated', '?')} {b.get('label', '')}) ==="
    )
    print(f"  passing: baseline {len(base_pass)} -> current {len(passing)}")
    if b.get("lynis") is not None and a.lynis is not None:
        dl = a.lynis - b["lynis"]
        tag = "OK" if dl >= 0 else "REGRESSION"
        print(f"  lynis:   baseline {b['lynis']} -> current {a.lynis} ({dl:+d}) [{tag}]")
    print(f"  REGRESSIONS (was pass, now FAIL): {len(regressions)}")
    for c in regressions:
        print(f"    ✗ {c}")
    print(f"  fixes (was fail, now pass): {len(fixes)}")
    for c in fixes:
        print(f"    ✓ {c}")

    lynis_reg = b.get("lynis") is not None and a.lynis is not None and a.lynis < b["lynis"]
    better = not regressions and len(passing) >= len(base_pass) and not lynis_reg
    if a.reset:
        if not a.label:
            sys.exit("--reset needs a --label saying WHY the baseline is re-anchored")
        save(bpath, a, passing, failing)
        print(f"  -> baseline RE-ANCHORED: {a.label}")
    elif a.update and better:
        save(bpath, a, passing, failing)
        print("  -> baseline updated (new best)")
    elif a.update:
        print("  -> baseline NOT updated (regression or fewer passes)")
    return 1 if (regressions or lynis_reg) else 0


if __name__ == "__main__":
    sys.exit(main())
