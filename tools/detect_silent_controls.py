#!/usr/bin/env python3
"""Find controls that produced NO OUTPUT, and therefore measured nothing.

    tools/detect_silent_controls.py <scan.json> [--json]

Why this exists, and why it is stronger than the lint next to it.

`tools/lint_shell_first_word.py` encodes the shapes we already know are broken: a command starting
with a shell keyword, or with a variable assignment. Both were found the hard way, hours apart, and
the second was found only because twelve pwquality controls failed together on a machine that was
configured correctly. A static lint can only ever catch the shapes someone already paid for.

This reads what actually happened. When `--sudo` prefixes the command string, anything the remote
shell cannot execute as a command yields an EMPTY stdout, and a matcher comparing that to "ok"
fails. The control then reports a deviation it never measured, which is the worst failure mode a
compliance tool has: a missed deviation costs one control, an invented one costs the operator's
trust in every green result.

An empty stdout where the control expected content is the signature, whatever the cause: a keyword,
an assignment, a binary off PATH, a command that does not exist on this OS, a typo in a pipeline.
That is the point: it does not need to know why.

Exit 1 if any control is silent, so a campaign can gate on it.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# An InSpec failure message looks like:
#     expected: "ok"
#          got: ""
GOT_RE = re.compile(r"got:\s*\"((?:[^\"\\]|\\.)*)\"", re.S)
EXPECTED_RE = re.compile(r"expected:\s*\"((?:[^\"\\]|\\.)*)\"", re.S)


def silent_results(report: dict):
    """Yield (control_id, title, code_desc, expected) for every test whose command returned
    nothing while being compared against a non-empty expectation."""
    for profile in report.get("profiles", []):
        for control in profile.get("controls", []):
            cid = control.get("id", "?")
            title = control.get("title") or ""
            for result in control.get("results", []):
                if result.get("status") != "failed":
                    continue
                msg = result.get("message") or ""
                got = GOT_RE.search(msg)
                exp = EXPECTED_RE.search(msg)
                if not got or not exp:
                    continue
                # Empty output, against an expectation that wanted something. A control that
                # legitimately expects "" is not silent, it is asserting emptiness.
                if got.group(1).strip() == "" and exp.group(1).strip() != "":
                    yield cid, title, result.get("code_desc", "")[:120], exp.group(1)


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv
    if not args:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2

    path = Path(args[0])
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - any unreadable report is a usage error here
        print(f"cannot read {path}: {exc}", file=sys.stderr)
        return 2

    found = list(silent_results(report))

    if as_json:
        print(
            json.dumps(
                [{"control": c, "title": t, "expected": e} for c, t, _, e in found], indent=2
            )
        )
        return 1 if found else 0

    total = sum(
        len(c.get("results", [])) for p in report.get("profiles", []) for c in p.get("controls", [])
    )
    if not found:
        print(f"silent-controls: none, across {total} test(s)")
        print(
            "silent-controls: every failing control produced output, so every verdict was measured"
        )
        return 0

    print(
        f"silent-controls: {len(found)} control(s) returned NOTHING and reported a verdict anyway\n"
    )
    for cid, _title, desc, expected in found[:40]:
        print(f"  {cid}")
        print(f"      expected {expected!r}, got nothing")
        if desc:
            print(f"      {desc}")
    if len(found) > 40:
        print(f"  ... and {len(found) - 40} more")
    print("\nA control with no output measured nothing. Its FAIL is invented, and if its matcher")
    print("had been written the other way its PASS would be invented too. Make the command's first")
    print("word something the shell executes (the renderer wraps keywords and assignments in")
    print("`sh -c`), then re-scan.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
