#!/usr/bin/env python3
"""Fill the README's command blocks from site/src/data/install.ts, the single source.

`tools/release/scenario.sh` already runs the documentation's own blocks on a fresh VM rather than a
hand-written copy, so a page that changes changes what gets proved. The README was outside that
arrangement: it carried retyped commands, and they drifted. It told a reader to `git clone` and
`mise run build` under a heading saying "Building from source is for contributors, not for users",
and offered to "swap the build for the signed binary once the first release ships" when four had.

A linter that forbids the drift is the weaker answer, because it notices after the fact and has to
be taught every shape. Generating the block removes the second copy: there is one source, the site
renders it, the scenario executes it, the README prints it.

Markers in README.md:

    <!-- doc-commands: first-scan -->
    ```bash
    ...generated...
    ```
    <!-- /doc-commands -->

Usage:
    python3 tools/gen_readme_commands.py            fill the blocks
    python3 tools/gen_readme_commands.py --check    fail if they are out of date (CI)
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
README = ROOT / "README.md"

# Named groups still occupy numbered slots, which cost one round trip: the first version rebuilt
# the block as `group(1) + rendered + group(4)`, meaning prefix + new body + OLD body, and dropped
# the closing fence entirely. Named throughout now, so the parts cannot be confused.
BLOCK = re.compile(
    r"(?P<open><!-- doc-commands: (?P<id>[a-z-]+) -->\n```(?P<lang>\w*)\n)"
    r"(?P<body>.*?)"
    r"(?P<close>```\n<!-- /doc-commands -->)",
    re.S,
)


def render(block_id: str) -> str:
    """The block as the site renders it, read through the same tool the scenario uses."""
    out = subprocess.run(  # noqa: S603
        [
            "mise",
            "exec",
            "--",
            "node",
            "--experimental-strip-types",
            str(ROOT / "tools/doc_commands.mjs"),
            "--id",
            block_id,
        ],
        capture_output=True,
        text=True,
        cwd=ROOT,
        check=False,
    )
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit(f"could not render the '{block_id}' block: {out.stderr.strip()[:200]}")
    return out.stdout.rstrip("\n") + "\n"


def main() -> int:
    check = "--check" in sys.argv[1:]
    text = README.read_text(encoding="utf-8")
    if not BLOCK.search(text):
        print("README.md carries no <!-- doc-commands: ... --> block")
        print("Nothing to generate, which also means nothing is kept in sync. Add the markers.")
        return 1

    stale: list[str] = []

    def fill(m: re.Match[str]) -> str:
        wanted = render(m.group("id"))
        if m.group("body") != wanted:
            stale.append(m.group("id"))
        return m.group("open") + wanted + m.group("close")

    new = BLOCK.sub(fill, text)

    if check:
        if stale:
            print(f"README.md is out of date with site/src/data/install.ts: {', '.join(stale)}")
            print("Run: mise run gen:readme")
            return 1
        n = len(BLOCK.findall(text))
        print(f"README: {n} command block(s) match install.ts")
        return 0

    README.write_text(new, encoding="utf-8")
    print(f"README: {len(BLOCK.findall(text))} block(s) filled from install.ts")
    if stale:
        print(f"  updated: {', '.join(stale)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
