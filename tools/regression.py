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
    """passing / failing / skipped control-id sets from a pavois (InSpec) scan JSON.

    SKIPPED is its own set, and that is the point. It used to be folded into `passing`: the guard
    below read "no assertion ran" and skipped controls with an EMPTY results list, but a control
    held back by `only_if` or by a waiver has results, with status `skipped`. It therefore reached
    the next line, had no `failed` result, and was recorded as PASSING. Measured on a real debian12
    scan: 299 passed, 281 failed, 82 skipped, and all 82 were counted as passes.

    The regression that hides behind that is the one this tool exists to catch: a control that
    starts being SKIPPED where it used to PASS (a guard added, a package removed, an `only_if` that
    stops matching) stays on the same side of the comparison, nothing is reported, and the host has
    quietly stopped being audited on that point.
    """
    with open(scan_path) as f:
        d = json.load(f)
    passing, failing, skipped = set(), set(), set()
    for prof in d.get("profiles", []):
        for c in prof.get("controls", []):
            cid = c.get("id")
            results = c.get("results", [])
            if not cid:
                continue
            if not results:  # the control was not applicable at all: not a verdict either way
                continue
            statuses = {r.get("status") for r in results}
            if "failed" in statuses:
                failing.add(cid)
            elif statuses == {"skipped"}:
                skipped.add(cid)
            else:
                passing.add(cid)
    return passing, failing, skipped


def save(bpath, a, passing, failing, skipped):
    os.makedirs(BASELINE_DIR, exist_ok=True)
    data = {
        "os": a.os,
        "updated": datetime.date.today().isoformat(),
        "label": a.label,
        "lynis": a.lynis,
        "n_pass": len(passing),
        "n_fail": len(failing),
        "n_skip": len(skipped),
        "passing": sorted(passing),
        "failing": sorted(failing),
        # Recorded so the NEXT run can tell "was passing, now skipped" from "was already skipped".
        # A baseline written before this key existed cannot make that distinction, and the
        # comparison says so rather than inventing regressions.
        "skipped": sorted(skipped),
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

    passing, failing, skipped = extract(a.scan)
    bpath = os.path.join(BASELINE_DIR, a.os + ".json")

    if not os.path.exists(bpath):
        print(
            f"[{a.os}] no baseline yet: {len(passing)} passing, {len(failing)} failing, "
            f"{len(skipped)} skipped" + (f", lynis {a.lynis}" if a.lynis is not None else "")
        )
        if a.update or a.reset:  # --reset anchors a FIRST baseline too, not only a re-anchor
            save(bpath, a, passing, failing, skipped)
            print(f"  -> baseline created at {bpath}")
        return 0

    with open(bpath) as f:
        b = json.load(f)
    base_pass, base_fail = set(b["passing"]), set(b.get("failing", []))
    # A baseline written before `skipped` existed folded skipped controls into `passing`, so
    # `base_pass & skipped` on such a file reports every waived control as a regression. On debian12
    # that is 82 of them. The distinction is only meaningful once both sides record it; until then
    # the transition is reported as a NOTE and the file says so.
    knows_skipped = "skipped" in b
    base_skip = set(b.get("skipped", []))
    regressions = sorted(base_pass & failing)
    silenced = sorted(base_pass & skipped) if knows_skipped else []
    fixes = sorted(base_fail & passing)
    # A control the baseline never saw. Not a regression: it legitimately fails on a host nobody
    # hardened for it. But never silent either, because `base_pass & failing` cannot contain it and
    # `mise run regression` would otherwise report zero on a control that fails on every host.
    unseen_fail = sorted(failing - base_pass - base_fail - base_skip)

    print(
        f"=== regression check: {a.os} (baseline {b.get('updated', '?')} {b.get('label', '')}) ==="
    )
    print(f"  passing: baseline {len(base_pass)} -> current {len(passing)}")
    print(
        f"  skipped: {len(skipped)} control(s) asserted nothing on this run"
        + (f" (baseline: {len(base_skip)})" if knows_skipped else "")
    )
    if b.get("lynis") is not None and a.lynis is not None:
        dl = a.lynis - b["lynis"]
        tag = "OK" if dl >= 0 else "REGRESSION"
        print(f"  lynis:   baseline {b['lynis']} -> current {a.lynis} ({dl:+d}) [{tag}]")
    print(f"  REGRESSIONS (was pass, now FAIL): {len(regressions)}")
    for c in regressions:
        print(f"    ✗ {c}")
    print(f"  SILENCED (was pass, now SKIPPED): {len(silenced)}")
    for c in silenced:
        print(f"    ~ {c}")
    if not knows_skipped:
        print("    (baseline predates the skipped/passing distinction: re-anchor with --reset")
        print("     to make 'was passing, now skipped' detectable)")
    print(f"  new and failing (never in the baseline): {len(unseen_fail)}")
    for c in unseen_fail:
        print(f"    ! {c}")
    print(f"  fixes (was fail, now pass): {len(fixes)}")
    for c in fixes:
        print(f"    ✓ {c}")

    lynis_reg = b.get("lynis") is not None and a.lynis is not None and a.lynis < b["lynis"]
    better = not regressions and not silenced and len(passing) >= len(base_pass) and not lynis_reg
    if a.reset:
        if not a.label:
            sys.exit("--reset needs a --label saying WHY the baseline is re-anchored")
        save(bpath, a, passing, failing, skipped)
        print(f"  -> baseline RE-ANCHORED: {a.label}")
    elif a.update and better:
        save(bpath, a, passing, failing, skipped)
        print("  -> baseline updated (new best)")
    elif a.update:
        print("  -> baseline NOT updated (regression or fewer passes)")
    # A control that stopped asserting is a regression: the host is no longer audited on it.
    return 1 if (regressions or silenced or lynis_reg) else 0


if __name__ == "__main__":
    sys.exit(main())
