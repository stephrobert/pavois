#!/usr/bin/env python3
"""Refuse a workflow that pins a shared action to a different commit than its siblings.

WHY THIS EXISTS

A new workflow was written with `step-security/harden-runner` pinned to v2.13.1 and
`actions/checkout` to v5.0.0, while the other twenty-three workflows in this repository were on
v2.21.1 and v7.0.1. Both pins were written from memory instead of copied from a sibling, which is
exactly the mistake nobody notices in review: a forty-character hex string looks equally plausible
whichever release it names.

Nothing offline caught it. actionlint checks syntax, zizmor checks patterns, poutine checks
exploitation chains, and all three are happy with a correctly-pinned obsolete action. It reached CI
and was caught there by Plumber, but only for harden-runner, and only because that particular
version carries published advisories:

    ISSUE-703  job `vm-bisect/bisect` references "step-security/harden-runner@f4a75cfd..."
               published advisories: GHSA-46g3-37rh-v698, GHSA-g699-3x6g-wm3g, GHSA-cpmj-h4f6-r6pq

The checkout pin, two years stale, went through untouched, because no advisory happened to name it.
An advisory database can only refuse what somebody has already reported; this refuses drift itself,
which does not need anyone to have noticed first.

WHAT IT CHECKS

Two things, both of which are already true of this repository today:

  1. Every action is pinned to a full 40-character commit SHA, never a tag or a branch. A tag moves,
     which is the whole reason the project's rules say to pin by digest.
  2. An action used by more than one workflow is pinned to the SAME commit everywhere. Actions in a
     monorepo (github/codeql-action/init and .../analyze) share one release, so they are grouped by
     owner and repository rather than by path.

Subpaths are grouped, local `./` actions and `docker://` references are skipped, and a reusable
workflow called with `uses:` is held to the same rule as an action.

    python3 tools/lint_action_pins.py             # check this repository
    python3 tools/lint_action_pins.py --selftest  # check the checker
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

# `uses: owner/repo[/sub][@ref]`, with an optional trailing `# comment`. Deliberately a regex and
# not a YAML parse: a workflow that does not parse is actionlint's problem, and this has to keep
# working on the file as written, including inside a matrix or an anchor.
USES = re.compile(r"^\s*-?\s*uses:\s*['\"]?([^'\"\s#]+)['\"]?\s*(?:#\s*(.*))?$")
SHA = re.compile(r"^[0-9a-f]{40}$")


def scan(text: str, where: str) -> list[tuple[str, str, str, str, int]]:
    """Every `uses:` in a workflow, as (owner/repo, ref, comment, file, line)."""
    found = []
    for n, line in enumerate(text.splitlines(), 1):
        m = USES.match(line)
        if not m:
            continue
        ref, comment = m.group(1), (m.group(2) or "").strip()
        if ref.startswith(("./", ".\\", "docker://")):
            continue  # a local action has no pin to get wrong
        target, _, at = ref.partition("@")
        parts = target.split("/")
        if len(parts) < 2:
            continue
        found.append(("/".join(parts[:2]), at, comment, where, n))
    return found


def offences(uses: list[tuple[str, str, str, str, int]]) -> list[str]:
    """Every pin that is not a SHA, and every action pinned two different ways."""
    out: list[str] = []
    by_action: dict[str, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))

    for action, ref, comment, where, line in uses:
        if not SHA.match(ref):
            out.append(
                f"{where}:{line}: {action} is pinned to {ref or '(nothing)'!r}, not a commit SHA. "
                "A tag moves; pin by digest."
            )
            continue
        by_action[action][ref].append(f"{where}:{line}{f' ({comment})' if comment else ''}")

    for action, refs in sorted(by_action.items()):
        if len(refs) < 2:
            continue
        # The majority is almost always the intended one, so name it rather than leaving the reader
        # to count: the fix is to move the odd ones onto it.
        ranked = sorted(refs.items(), key=lambda kv: (-len(kv[1]), kv[0]))
        winner, winner_at = ranked[0]
        detail = [f"{action} is pinned {len(refs)} different ways:"]
        detail.append(f"    {winner}  used by {len(winner_at)}, in {winner_at[0]}")
        for ref, at in ranked[1:]:
            detail.append(f"    {ref}  used by {len(at)}: {', '.join(at)}")
        detail.append(f"    Move the odd ones to {winner}.")
        out.append("\n".join(detail))
    return out


SELFTEST = [
    # (name, {filename: content}, expected number of offences)
    (
        "a repository that agrees with itself",
        {
            "a.yml": "    - uses: actions/checkout@" + "a" * 40 + " # v7.0.1\n",
            "b.yml": "    - uses: actions/checkout@" + "a" * 40 + " # v7.0.1\n",
        },
        0,
    ),
    (
        "the witness: two pins for one action must be refused",
        {
            "a.yml": "    - uses: actions/checkout@" + "a" * 40 + " # v7.0.1\n",
            "b.yml": "    - uses: actions/checkout@" + "b" * 40 + " # v5.0.0\n",
        },
        1,
    ),
    (
        "a tag instead of a digest",
        {"a.yml": "    - uses: actions/checkout@v4\n"},
        1,
    ),
    (
        "a bare action with no ref at all",
        {"a.yml": "    - uses: actions/checkout\n"},
        1,
    ),
    (
        "subpaths of one monorepo share a pin, and are not counted apart",
        {
            "a.yml": (
                "    - uses: github/codeql-action/init@" + "c" * 40 + "\n"
                "    - uses: github/codeql-action/analyze@" + "c" * 40 + "\n"
            )
        },
        0,
    ),
    (
        "subpaths of one monorepo pinned differently ARE an offence",
        {
            "a.yml": (
                "    - uses: github/codeql-action/init@" + "c" * 40 + "\n"
                "    - uses: github/codeql-action/analyze@" + "d" * 40 + "\n"
            )
        },
        1,
    ),
    (
        "a local action has no pin to get wrong",
        {"a.yml": "    - uses: ./.github/actions/thing\n"},
        0,
    ),
    (
        "a docker reference is not an action pin",
        {"a.yml": "    - uses: docker://alpine:3.20\n"},
        0,
    ),
    (
        "quoted, and with no leading dash",
        {"a.yml": "        uses: 'actions/cache@" + "e" * 40 + "'\n"},
        0,
    ),
    (
        "three ways is still one offence, and names the majority",
        {
            "a.yml": "    - uses: x/y@" + "a" * 40 + "\n",
            "b.yml": "    - uses: x/y@" + "a" * 40 + "\n",
            "c.yml": "    - uses: x/y@" + "b" * 40 + "\n",
            "d.yml": "    - uses: x/y@" + "f" * 40 + "\n",
        },
        1,
    ),
]


def selftest() -> int:
    bad = 0
    for name, files, expected in SELFTEST:
        uses: list[tuple[str, str, str, str, int]] = []
        for fname, text in files.items():
            uses += scan(text, fname)
        got = offences(uses)
        if len(got) != expected:
            bad += 1
            print(f"  FAIL  {name}: expected {expected} offence(s), got {len(got)}")
            for line in got:
                print(f"          {line.splitlines()[0]}")
        else:
            print(f"  ok    {name}")
    # The majority has to be named correctly, or the message sends the reader to the wrong pin.
    uses = scan("    - uses: x/y@" + "a" * 40 + "\n", "a.yml") * 2
    uses += scan("    - uses: x/y@" + "b" * 40 + "\n", "b.yml")
    msg = offences(uses)[0]
    if ("a" * 40) not in msg.splitlines()[1]:
        bad += 1
        print("  FAIL  the majority pin is not the one offered as the fix")
    else:
        print("  ok    the majority pin is the one offered as the fix")
    print(f"\nlint:action-pins selftest: {len(SELFTEST) + 1 - bad}/{len(SELFTEST) + 1}")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--selftest", action="store_true", help="check the checker and exit")
    ap.add_argument("--root", default=".", help="repository root")
    args = ap.parse_args()
    if args.selftest:
        return selftest()

    root = Path(args.root)
    paths = sorted(root.glob(".github/workflows/*.y*ml"))
    paths += sorted(root.glob(".github/actions/*/action.y*ml"))
    if not paths:
        print("lint:action-pins: no workflows found, which is not something to pass quietly")
        return 1

    uses: list[tuple[str, str, str, str, int]] = []
    for p in paths:
        uses += scan(p.read_text(encoding="utf-8"), str(p.relative_to(root)))

    problems = offences(uses)
    if problems:
        print("lint:action-pins: pins that disagree with the rest of the repository\n")
        for p in problems:
            print(f"  {p}\n")
        return 1
    actions = {a for a, *_ in uses}
    print(
        f"lint:action-pins: {len(uses)} uses of {len(actions)} actions, every one pinned and agreed"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
