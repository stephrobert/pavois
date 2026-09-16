#!/usr/bin/env python3
"""FAIL if a control's command would lose its privileges, or run nothing at all, under --sudo.

The transport prefixes `sudo ` to the command STRING, which the remote shell reads as
`sudo cmd1; cmd2`. Measured on a live debian12 target, not inferred:

    id -u                        ->  0       (root)
    echo "$(id -u)"              ->  1000    (NOT root)
    for s in ufw ...; do ...     ->  ""      `sudo for` is not a command: no output at all

So a control whose command starts with a shell keyword produces an EMPTY stdout, and its matcher
then reports a verdict on something it never measured. Nineteen controls did exactly that, among
them firewall-present and firewall-default-deny, which claimed a HIGH deviation on a host whose
nftables input chain was already `policy drop`.

An invented deviation is worse than a missed one. A missed deviation costs one control; a deviation
invented on a correct machine teaches the operator to distrust the green results too, and a
compliance tool nobody believes is worth nothing.

The renderer now wraps those commands in `sh -c '...'` (tools/render_reference.py), which makes the
first word a real binary so `sudo sh -c '...'` runs the whole line as root. This lint is the guard
that the wrapping actually happened, checked on the RENDERED corpus, which is what runs.

    mise run lint:shell-first-word
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "profiles" / "linux"

# A command starting with one of these is not a command at all once `sudo ` is prefixed.
KEYWORDS = {"if", "for", "while", "until", "case", "test", "["}

# `sudo NAME=value ...` is an environment assignment, not a command: nothing runs. The first rule
# written here was "the first word must not be a shell keyword", and it was wrong. The rule is
# "the first word must be something the shell executes", and an assignment is not.
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

# Binaries that need root, live outside the unprivileged PATH, or both. Inside a $( ) they run as
# the login user, which on a Debian cloud image means /usr/local/bin:/usr/bin:/bin:/usr/games.
PRIVILEGED = {
    "sysctl",
    "sshd",
    "auditctl",
    "aa-status",
    "nft",
    "iptables",
    "ip6tables",
    "ufw",
    "firewall-cmd",
    "grubby",
    "sestatus",
    "getenforce",
    "semanage",
    "lvs",
    "pvs",
    "vgs",
    "dmsetup",
    "blkid",
    "modprobe",
    "lsmod",
    "dconf",
    "augenrules",
    "pam_tally2",
    "faillock",
}
PRIV_RE = re.compile(r"(?<![\w/-])(" + "|".join(map(re.escape, sorted(PRIVILEGED))) + r")(?![\w-])")
# Ruby concatenates ADJACENT string literals, so `command('a''b')` is one string. A pattern
# matching a single literal silently skips those, and misc-postfix-anti-vrfy (which starts with
# `if`) went unwrapped and unreported because of exactly that. Match everything up to the
# closing `) do`, then strip the literal quoting.
COMMAND_RE = re.compile(r"command\((\s*'(?:[^'\\]|\\.)*'(?:\s*'(?:[^'\\]|\\.)*')*)\)")
CONTROL_RE = re.compile(r"^control '([^']+)' do", re.M)
SUBST_RE = re.compile(r"\$\(([^()]*(?:\([^()]*\)[^()]*)*)\)")


def control_at(text: str, pos: int) -> str:
    name = "?"
    for m in CONTROL_RE.finditer(text):
        if m.start() > pos:
            break
        name = m.group(1)
    return name


def main() -> int:
    if not CORPUS.is_dir():
        print("lint:shell-first-word: no rendered corpus; run `mise run render` first")
        return 0

    problems: list[tuple[str, str, str, str]] = []
    checked = 0

    for rb in sorted(CORPUS.glob("*/controls/*.rb")):
        text = rb.read_text(encoding="utf-8")
        for m in COMMAND_RE.finditer(text):
            checked += 1
            parts = re.findall(r"'((?:[^'\\]|\\.)*)'", m.group(1))
            script = "".join(parts).replace("\\'", "'").replace("\\\\", "\\")
            ctl = control_at(text, m.start())
            os_name = rb.parent.parent.name

            first = script.strip().split(None, 1)[0] if script.strip() else ""
            if first in KEYWORDS:
                problems.append(
                    (os_name, ctl, "starts with the shell keyword " + first, script[:80])
                )
                continue
            if ASSIGNMENT_RE.match(first):
                name = first.split("=")[0]
                problems.append((os_name, ctl, f"starts with the assignment {name}=", script[:80]))
                continue

            # A privileged read inside a substitution runs unprivileged. `sh -c '...'` makes the
            # whole line root, so a wrapped command is fine.
            if not script.lstrip().startswith("sh -c "):
                for sub in SUBST_RE.findall(script):
                    hit = PRIV_RE.search(sub)
                    if hit:
                        problems.append(
                            (os_name, ctl, f"privileged `{hit.group(1)}` inside $( )", script[:80])
                        )
                        break

    if problems:
        print(
            f"lint:shell-first-word: {len(problems)} control(s) would not measure what they claim\n"
        )
        for os_name, ctl, why, script in problems[:40]:
            print(f"  {os_name:<12} {ctl:<46} {why}")
            print(f"       {script}")
        if len(problems) > 40:
            print(f"  ... and {len(problems) - 40} more")
        print("\nWrap the command so its first word is a real binary. The renderer does this")
        print("automatically for shell keywords; a privileged command inside $( ) has to be")
        print("restructured so the privileged read comes first.")
        return 1

    print(f"lint:shell-first-word: {checked} command(s) checked")
    print("lint:shell-first-word: every command runs as the privilege it needs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
