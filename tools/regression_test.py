#!/usr/bin/env python3
"""Prove `mise run regression` reports the regressions it claims to.

The tool is the gate CLAUDE.md makes non-negotiable at every rules change, and it answered a
narrower question than the rule assumes (#304):

  - a control SKIPPED where it used to pass was recorded as passing on both sides, so the host
    quietly stopped being audited on that point and nothing was reported. Measured on a real
    debian12 scan: 299 passed, 281 failed, 82 skipped, all 82 counted as passes.
  - a control absent from the baseline could never appear in `base_pass & failing`, so ADDING a
    control that fails on the golden host produced a green run, which is the permanent FAIL the
    rule forbids.

Each case here builds two scan JSONs in a temp tree and asserts what the tool says about the pair.
Run: python3 tools/regression_test.py
"""

from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOL = ROOT / "tools/regression.py"


def scan(path: pathlib.Path, passed: list[str], failed: list[str], skipped: list[str]) -> None:
    """A scan JSON in the shape InSpec produces, with the three outcomes."""
    controls = []
    for cid in passed:
        controls.append({"id": cid, "results": [{"status": "passed"}]})
    for cid in failed:
        controls.append({"id": cid, "results": [{"status": "failed", "message": "nope"}]})
    for cid in skipped:
        controls.append({"id": cid, "results": [{"status": "skipped", "skip_message": "only_if"}]})
    path.write_text(json.dumps({"profiles": [{"controls": controls}]}), encoding="utf-8")


def run(tree: pathlib.Path, scan_path: pathlib.Path, *extra: str) -> tuple[int, str]:
    p = subprocess.run(  # noqa: S603
        [sys.executable, str(TOOL), str(scan_path), "--os", "testos", *extra],
        capture_output=True,
        text=True,
        cwd=tree,
        check=False,
    )
    return p.returncode, p.stdout + p.stderr


def main() -> int:
    failures = 0

    def check(name: str, cond: bool, detail: str = "") -> None:
        nonlocal failures
        if cond:
            print(f"  ok   {name}")
        else:
            failures += 1
            print(f"  FAIL {name}\n{detail}")

    print("the regression gate reports:")
    with tempfile.TemporaryDirectory() as d:
        tree = pathlib.Path(d)
        (tree / "docs/reference/baselines").mkdir(parents=True)
        base_scan = tree / "base.json"
        scan(base_scan, passed=["a", "b", "c"], failed=["d"], skipped=["e"])
        rc, out = run(tree, base_scan, "--reset", "--label", "anchor")
        check(
            "an anchored baseline separates skipped from passing",
            "3 passing" in out and "1 skipped" in out,
            out,
        )

        # 1. The defect this file exists for: a control that stops asserting.
        s = tree / "silenced.json"
        scan(s, passed=["a", "b"], failed=["d"], skipped=["c", "e"])
        rc, out = run(tree, s)
        check(
            "a control SKIPPED where it used to pass is a regression",
            rc == 1 and "SILENCED" in out and "~ c" in out,
            out,
        )

        # 2. A control the baseline never saw, failing.
        s = tree / "new.json"
        scan(s, passed=["a", "b", "c"], failed=["d", "zz-new"], skipped=["e"])
        rc, out = run(tree, s)
        check(
            "a NEW control that fails is named, not silently ignored",
            "! zz-new" in out,
            out,
        )
        check(
            "and it is not called a regression (it never passed)",
            "REGRESSIONS (was pass, now FAIL): 0" in out,
            out,
        )

        # 3. The classic regression still works.
        s = tree / "reg.json"
        scan(s, passed=["a", "b"], failed=["c", "d"], skipped=["e"])
        rc, out = run(tree, s)
        check(
            "a control that went from pass to FAIL is still a regression",
            rc == 1 and "✗ c" in out,
            out,
        )

        # 4. No change is green.
        rc, out = run(tree, base_scan)
        check("an identical scan is green", rc == 0, out)

        # 5. A control that was already skipped stays quiet.
        s = tree / "stillskip.json"
        scan(s, passed=["a", "b", "c"], failed=["d"], skipped=["e"])
        rc, out = run(tree, s)
        check(
            "a control that was ALREADY skipped is not reported", rc == 0 and "~ e" not in out, out
        )

    print("\nand on a baseline written before the distinction existed:")
    with tempfile.TemporaryDirectory() as d:
        tree = pathlib.Path(d)
        bdir = tree / "docs/reference/baselines"
        bdir.mkdir(parents=True)
        # The old format: skipped ids folded into `passing`, and no `skipped` key at all.
        (bdir / "testos.json").write_text(
            json.dumps({"os": "testos", "passing": ["a", "b", "c", "e"], "failing": ["d"]}),
            encoding="utf-8",
        )
        s = tree / "now.json"
        scan(s, passed=["a", "b", "c"], failed=["d"], skipped=["e"])
        rc, out = run(tree, s)
        check(
            "an old baseline does not turn its waived controls into regressions",
            rc == 0 and "~ e" not in out,
            out,
        )
        check("and it says why it cannot tell", "predates" in out, out)

    if failures:
        print(f"\n{failures} case(s) wrong: the gate does not measure what it claims.")
        return 1
    print("\nthe gate sees a silenced control, a new failing one, and a real regression.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
