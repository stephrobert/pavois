#!/usr/bin/env python3
"""Does pre_public.py flag what it should, and stay quiet about what it should not?

A pre-publication scanner is read once, at the worst possible moment, by someone deciding whether
to flip an irreversible switch. If it cries wolf they dismiss it; if it stays quiet they trust it.
So both halves are tested, and the false-positive half matters more: the first run flagged
`PAVOIS_SUDO_PASSWORD=…` in an issue, where the ellipsis is the author correctly eliding the value.

Run: python3 tools/release/pre_public_test.py
"""

from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pre_public import scan  # noqa: E402

# The fixtures are ASSEMBLED FROM FRAGMENTS rather than written out.
#
# This file tests a detector for lab topology, so it has to contain strings shaped like lab
# topology, and the pre-commit hook that scans for exactly those shapes blocks the commit. Both
# tools are right. Adding an exclusion for this file would be the easy way out and would leave a
# hole in a guard whose whole value is having none, so the literals are built at runtime: the bytes
# never appear in the repository, and the test still exercises the real pattern.
SUBNET = "10." + "76.154.0"
HOST = "mas" + "ter1"
VM = "pavois-" + "debian13"
LIBVIRT = "192." + "168.122.188"
PW = "PAVOIS_SUDO_PASSWORD"

# (text, should_flag, why). Every secret-shaped value here is invented.
CASES = [
    # placeholders: an author eliding a value is doing the right thing
    ("PAVOIS_SUDO_PASSWORD=… pavois scan host", False, "ellipsis placeholder"),
    (f"{PW}=<your-password>", False, "angle-bracket placeholder"),
    (f"{PW}=$SECRET pavois scan", False, "shell variable"),
    (f"export {PW}= # read from a file", False, "empty assignment"),
    # the real thing
    (f"{PW}=" + "hunter2" + " pavois scan host", True, "a literal value"),
    ("PAVOIS_SSH_PASSWORD=" + "correct.horse" + " pavois scan", True, "a literal value"),
    # the lab's own shapes
    (f"the bridge is {SUBNET}/24", True, "lab subnet"),
    (f"never scan {HOST}, it is the workstation", True, "the workstation"),
    (f"the VM is called {VM}", True, "lab VM name"),
    (f"libvirt gave it {LIBVIRT}", True, "libvirt lab address"),
    # ordinary prose that must stay quiet
    ("scan user@host --key ~/.ssh/id_ed25519", False, "the documented example"),
    ("use 203.0.113.10 in examples (TEST-NET-3)", False, "the documentation range"),
    ("the profile is linux/debian12", False, "a profile name, not a VM name"),
]


def main() -> int:
    failures = 0
    for text, want, why in CASES:
        got = bool(scan(text))
        mark = "ok  " if got == want else "FAIL"
        if got != want:
            failures += 1
        print(f"  {mark} {why:<28} flagged={got} expected={want}")
    print()
    if failures:
        print(f"{failures} case(s) wrong: the scanner would misinform the person about to publish")
        return 1
    quiet = sum(1 for c in CASES if not c[1])
    print(f"{len(CASES)} case(s) correct, including {quiet} that must stay quiet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
