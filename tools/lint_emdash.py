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

# Spelled by code point on purpose: writing the characters literally would make this file its own
# first offender, and excluding it by name would leave a blind spot in the one file nobody rereads.
BANNED = {
    chr(0x2014): "em-dash",
    chr(0x2013): "en-dash",
}

# The literal character is only one of the ways an em-dash reaches a reader. A JS/TS/JSON string
# escape and an HTML entity both render as one, and this linter used to walk straight past them:
# a title written as a backslash-u escape in an .astro file shipped on the site while `lint:emdash`
# reported clean. Same assembly-by-pieces as above, for the same reason.
_BS, _AMP = chr(0x5C), chr(0x26)
ESCAPED = {
    _BS + "u2014": "escaped em-dash",
    _BS + "u2013": "escaped en-dash",
    _AMP + "mdash;": "em-dash HTML entity",
    _AMP + "ndash;": "en-dash HTML entity",
    _AMP + "#8212;": "em-dash numeric entity",
    _AMP + "#8211;": "en-dash numeric entity",
    _AMP + "#x2014;": "em-dash hex entity",
    _AMP + "#x2013;": "en-dash hex entity",
}
# The site ships a vendored sample report and third-party CSS; neither is ours to reword.
SKIP_PREFIXES = ("site/public/sample-", "site/node_modules/", "docs/reference/oscap-")


def offences(line: str) -> list[str]:
    """Every banned dash form on one line, literal or written as an escape."""
    found = [name for ch, name in BANNED.items() if ch in line]
    lowered = line.lower()  # catches the uppercase hex entity, and costs nothing on the rest
    found += [name for pat, name in ESCAPED.items() if pat in lowered]
    return found


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True)
    return [f for f in out.stdout.splitlines() if not f.startswith(SKIP_PREFIXES)]


def selftest() -> int:
    """A linter nobody can see fail is a linter nobody can trust.

    The witness case matters as much as the offenders: a pattern list built from string
    concatenation is one typo away from matching everything or nothing.
    """
    cases = [
        (chr(0x2014), True, "literal em-dash"),
        (chr(0x2013), True, "literal en-dash"),
        (_BS + "u2014", True, "escaped em-dash"),
        (_BS + "U2014", True, "escaped em-dash, uppercase"),
        (_AMP + "mdash;", True, "entity"),
        (_AMP + "#8212;", True, "numeric entity"),
        (_AMP + "#X2014;", True, "hex entity, uppercase"),
        ("a - b, a-b, 100--200, " + _BS + "u00e9, " + _AMP + "amp;", False, "witness: clean line"),
    ]
    bad = 0
    for line, want, label in cases:
        got = bool(offences(line))
        if got != want:
            print(f"  selftest FAIL [{label}]: expected {want}, got {got}", file=sys.stderr)
            bad += 1
    print(f"lint:emdash selftest: {len(cases) - bad}/{len(cases)} cases")
    return 1 if bad else 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()

    hits: list[str] = []
    for path in tracked_files():
        try:
            with open(path, encoding="utf-8") as fh:
                for n, line in enumerate(fh, 1):
                    for name in offences(line):
                        hits.append(f"{path}:{n}: {name} in: {line.strip()[:88]}")
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError):
            continue  # binaries, submodules, files removed since ls-files

    if hits:
        print(f"lint:emdash: {len(hits)} banned dash(es)", file=sys.stderr)
        for h in hits[:40]:
            print("  " + h, file=sys.stderr)
        if len(hits) > 40:
            print(f"  ... and {len(hits) - 40} more", file=sys.stderr)
        print(
            "\n  Reword the sentence. Do NOT bulk-replace: turning `a - b` into `a: b` inside\n"
            "  YAML makes an unquoted scalar a mapping, which is how four files broke last time.",
            file=sys.stderr,
        )
        return 1

    print("lint:emdash: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
