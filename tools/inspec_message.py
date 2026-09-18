#!/usr/bin/env python3
"""Read what a control OBSERVED out of an InSpec failure message.

Two tools ask the same question of every failure: what did the command actually return? Both
carried the same pattern, and it only understood one of the shapes InSpec produces:

    GOT_RE = re.compile(r"got:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", re.S)

Measured on a real debian12 scan, 391 failures:

    140   expected "" to match /re/        the command returned NOTHING   <- invisible
    128   other rspec phrasings                                           <- invisible
     73   expected: "x"  got: "y"          the only shape it read
     50   expected: X  got: Y  (cmp)       unquoted                       <- invisible

`validate_run.py` rule R1 exists to name exactly the first line: a control that reported a
deviation having measured nothing. It fired on ZERO of those 140. The run was saved by a
coarser heuristic (68, 113, 22 controls failing with an identical message), which says
"suspect one cause" rather than "this control measured nothing".

The shapes, and why the `match` one is not what it looks like:

    expected: "ok"        got: "ko"          eq, quoted
    expected: YESCRYPT    got: SHA512        cmp, unquoted
    expected "" to match /(-k +|key=)perm_mod/    match

In the third, rspec puts the ACTUAL value after `expected`: it reads "expected <what I got> to
match <what I wanted>". So `expected ""` there means the command returned nothing, and reading it
as the wanted value gets the direction backwards.

Returns (observed, wanted, readable). `readable` is False when none of the shapes matched, and
the callers report that count rather than treating it as "nothing to see": a detector that
silently examines a fifth of its input gives a confidence it has not earned.
"""

from __future__ import annotations

import re

# expected: "x"   got: "y"      (eq, include, and friends)
_QUOTED = re.compile(r'expected:\s*"((?:[^"\\]|\\.)*)".*?got:\s*"((?:[^"\\]|\\.)*)"', re.S)
# expected: X     got: Y        (cmp prints the values bare)
_BARE = re.compile(r"expected:\s*(\S.*?)\s*\n\s*got:\s*(\S.*?)\s*(?:\n|$)", re.S)
# expected <actual> to match /re/      and the `not to match` negation
# The regex is taken to the end of the LINE, not to the first space: `/(-k +|key=)perm_mod\b/`
# contains one, and `\S+` truncated it to `/(-k`, which turns the message into a puzzle.
_MATCH = re.compile(r'expected\s+"((?:[^"\\]|\\.)*)"\s+(not\s+)?to\s+match\s+(.+?)\s*$', re.M)
# expected it to be <= 365 \n got: 99999      (cmp with an operator: no `expected:` label)
_CMP_OP = re.compile(r"expected it to be\s+(.*?)\s*\n\s*got:\s*(\S.*?)\s*(?:\n|$)", re.S)


def evidence(message: str) -> tuple[str | None, str | None, bool]:
    """(observed, wanted, readable) from one InSpec failure message."""
    if not message:
        return None, None, False

    m = _QUOTED.search(message)
    if m:
        return m.group(2), m.group(1), True

    m = _MATCH.search(message)
    if m:
        # group(1) is the ACTUAL value; the regex is what was wanted.
        return m.group(1), m.group(3), True

    m = _CMP_OP.search(message)
    if m:
        return m.group(2), m.group(1), True

    m = _BARE.search(message)
    if m:
        return m.group(2), m.group(1), True

    return None, None, False


def measured_nothing(message: str) -> bool:
    """True when the control produced a verdict on an empty observation.

    This is the whole point of the exercise: an empty output with a non-empty expectation means the
    command did not run, or ran and said nothing, and the matcher then decided anyway.
    """
    observed, wanted, readable = evidence(message)
    if not readable or observed is None:
        return False
    return observed.strip() == "" and (wanted or "").strip() != ""
