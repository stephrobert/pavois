#!/usr/bin/env python3
"""Refuse the em-dash, anywhere in the tracked tree.

Two reasons it is banned here, and the second is the one that costs money:

  1. It reads as machine-written prose.
  2. It is not ASCII, and this repo generates shell, GRUB command lines, sysctl drop-ins and
     kernel config from its own documentation. An em-dash that reaches a generated file has
     already broken `harden apply` once, on debian13.

Deleting them in bulk is how the last pass introduced four invalid YAML files: `word - word`
rewritten as `word: word` turns an unquoted scalar into a mapping. So this only REPORTS, with the
line, and leaves the wording to a human who can see the sentence.

  mise run lint:emdash
"""

from __future__ import annotations

import subprocess
import sys

BANNED = {
    "—": "em-dash",
    "–": "en-dash",
}
# The site ships a vendored sample report and third-party CSS; neither is ours to reword.
SKIP_PREFIXES = ("site/public/sample-", "site/node_modules/", "docs/reference/oscap-")


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True)
    return [f for f in out.stdout.splitlines() if not f.startswith(SKIP_PREFIXES)]


def main() -> int:
    hits: list[str] = []
    for path in tracked_files():
        try:
            with open(path, encoding="utf-8") as fh:
                for n, line in enumerate(fh, 1):
                    for ch, name in BANNED.items():
                        if ch in line:
                            hits.append(f"{path}:{n}: {name} in: {line.strip()[:88]}")
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            continue  # binaries, submodules, files removed since ls-files

    if hits:
        print(f"lint:emdash: {len(hits)} banned dash(es)", file=sys.stderr)
        for h in hits[:40]:
            print("  " + h, file=sys.stderr)
        if len(hits) > 40:
            print(f"  ... and {len(hits) - 40} more", file=sys.stderr)
        print("\n  Reword the sentence. Do NOT bulk-replace: turning `a - b` into `a: b` inside\n"
              "  YAML makes an unquoted scalar a mapping, which is how four files broke last time.",
              file=sys.stderr)
        return 1

    print("lint:emdash: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
