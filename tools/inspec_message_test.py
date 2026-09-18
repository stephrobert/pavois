#!/usr/bin/env python3
"""Prove the failure-message reader recognises every shape InSpec produces, and admits the rest.

The pattern it replaces read one shape and silently ignored three. On a real debian12 scan it took
evidence from 73 of 391 failures and reported "no sign that any verdict was invented", while 140
controls had returned nothing and reported a deviation anyway (#303).

Every case below is a message copied from a real scan, not invented. The last group is the one that
matters most: a shape the reader cannot parse must come back `readable=False`, never as a silent
pass, because that is the difference between "examined and cleared" and "not examined".

Run: python3 tools/inspec_message_test.py
"""

from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from inspec_message import evidence, measured_nothing  # noqa: E402

# (label, message, expected observed, expected wanted, measured nothing?)
CASES = [
    (
        "eq, quoted, non-empty",
        'expected: "ok"\n     got: "ko"\n\n(compared using ==)',
        "ko",
        "ok",
        False,
    ),
    (
        "eq, quoted, EMPTY output",
        'expected: "ok"\n     got: ""\n\n(compared using ==)',
        "",
        "ok",
        True,
    ),
    (
        "cmp, bare values",
        "expected: YESCRYPT\n     got: SHA512\n\n(compared using `cmp` matcher)",
        "SHA512",
        "YESCRYPT",
        False,
    ),
    (
        "cmp with an operator",
        "expected it to be <= 365\n     got: 99999\n\n(compared using `cmp` matcher)",
        "99999",
        "<= 365",
        False,
    ),
    (
        "match, EMPTY output (the 140)",
        'expected "" to match /(-k +|key=)perm_mod\\b/\n'
        'Diff:\n@@ -1 +1 @@\n-/(-k +|key=)perm_mod\\b/\n+""\n',
        "",
        "/(-k +|key=)perm_mod\\b/",
        True,
    ),
    (
        "match, non-empty output",
        'expected "yescrypt" to match /sha512/\n',
        "yescrypt",
        "/sha512/",
        False,
    ),
    (
        "not to match",
        'expected "Debian GNU/Linux 12" not to match /\\\\[smrvlSMRVL]/\n',
        "Debian GNU/Linux 12",
        "/\\\\[smrvlSMRVL]/",
        False,
    ),
]

UNREADABLE = [
    ("a shape nobody has modelled", "undefined method `foo' for nil:NilClass"),
    ("an empty message", ""),
    ("prose with no verdict in it", "Control Source Code Error"),
]


def main() -> int:
    failures = 0
    print("the reader takes evidence from:")
    for label, msg, want_obs, want_wanted, want_silent in CASES:
        obs, wanted, readable = evidence(msg)
        ok = readable and obs == want_obs and wanted == want_wanted
        silent_ok = measured_nothing(msg) == want_silent
        if ok and silent_ok:
            print(f"  ok   {label}")
        else:
            failures += 1
            print(
                f"  FAIL {label}\n"
                f"       observed={obs!r} (wanted {want_obs!r})\n"
                f"       wanted={wanted!r} (wanted {want_wanted!r})\n"
                f"       measured_nothing={measured_nothing(msg)} (wanted {want_silent})"
            )

    print("\nand refuses to guess at:")
    for label, msg in UNREADABLE:
        obs, wanted, readable = evidence(msg)
        if not readable and not measured_nothing(msg):
            print(f"  ok   {label}: reported unreadable, not cleared")
        else:
            failures += 1
            print(f"  FAIL {label}: readable={readable} observed={obs!r}")

    if failures:
        print(f"\n{failures} case(s) wrong: the reader does not read what it claims.")
        return 1
    print("\nfour shapes read, and an unknown one admitted rather than passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
