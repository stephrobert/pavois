#!/usr/bin/env python3
"""Refuse a wrapper that only works on the machine it was written on.

`bin/pavois` is the entry point CLAUDE.md documents, the default of tools/harden_validate.sh
(`PAVOIS_BIN:-bin/pavois`), and the command this project's own non-negotiable rule names: "verified
by a real `bin/pavois scan` on the debian12 VM".

On 2026-09-04 it was committed holding one line:

    exec "/tmp/claude-1000/<session>/scratchpad/wt-go/go/pavois" "$@"

and every clone of the repository answered `No such file or directory` for a fortnight.

WHY RUNNING IT DOES NOT CATCH THIS. tools/testplan.py already asks for `bin/pavois version` when
this file changes, and that check would have PASSED the day it broke: the temporary directory
existed on that machine at that moment. A path baked in at commit time is not wrong on the machine
that baked it, which is the whole problem. It is wrong everywhere else, and later.

So this reads the file instead of executing it, and refuses what cannot be true for someone else:

  - an absolute path in an `exec` or a variable assignment. A wrapper resolves from its OWN
    location (`dirname "$0"`), never from a path decided when it was written.
  - any mention of /tmp, /home, or a session scratchpad, anywhere.

It does not try to be a shell parser. Every rule below is a fact about a line of text, which is
what makes it cheap enough to sit in the pre-push hook.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WRAPPERS = ["bin/pavois"]

# An absolute path where the wrapper decides what to run. `exec /usr/bin/env` is not this: the
# pattern is anchored on the FIRST word after exec, and /usr/bin/env is allowed by the shebang rule
# below rather than here.
RE_EXEC_ABS = re.compile(r"^\s*exec\s+\"?(/[^\s\"]+)")
RE_ASSIGN_ABS = re.compile(r"^\s*(?:local\s+)?\w+=\"?(/(?:tmp|home|Users|var/tmp)/[^\s\"]*)")
# Machine-specific roots, anywhere on the line, including inside a comment that got copied around.
RE_MACHINE = re.compile(r"(/tmp/|/home/[^/\s\"]+|/Users/[^/\s\"]+|scratchpad)")

# The one place those strings are legitimate: a comment that RECORDS the defect. A line that
# explains the trap must be allowed to quote it, or the guard forbids its own documentation.
EXPLAINED = "committed holding"


def problems(path: pathlib.Path, text: str) -> list[str]:
    bad: list[str] = []
    rel = path.relative_to(ROOT)
    in_comment_block = False
    for n, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        is_comment = stripped.startswith("#")
        if is_comment and EXPLAINED in text and stripped != "#":
            # A comment may quote the broken form; code may not. Comments are checked for nothing
            # else, deliberately: the cost of a false positive here is that somebody deletes the
            # explanation to make the linter shut up.
            in_comment_block = True
            continue
        in_comment_block = False

        m = RE_EXEC_ABS.match(line)
        if m and not m.group(1).startswith("/usr/bin/env"):
            bad.append(
                f"{rel}:{n}: execs an absolute path ({m.group(1)}).\n"
                f"        A wrapper resolves from its own location:\n"
                f'        here="$(cd "$(dirname "$0")/.." && pwd)"'
            )
        m = RE_ASSIGN_ABS.match(line)
        if m:
            bad.append(f"{rel}:{n}: assigns a machine-specific path ({m.group(1)})")
        if not is_comment and not in_comment_block:
            m = RE_MACHINE.search(line)
            if m:
                bad.append(
                    f"{rel}:{n}: names a path that exists only on one machine ({m.group(1)!r}): "
                    f"{stripped[:60]}"
                )
    if not any("dirname" in line for line in text.splitlines()):
        bad.append(
            f"{rel}: nothing resolves from the script's own location. "
            f'Expected `dirname "$0"`, without which the wrapper depends on where it is '
            f"called from."
        )
    return bad


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()

    bad: list[str] = []
    for w in WRAPPERS:
        p = ROOT / w
        if not p.exists():
            bad.append(f"{w}: missing, and CLAUDE.md documents it as the entry point")
            continue
        if not p.stat().st_mode & 0o111:
            bad.append(f"{w}: not executable")
        bad.extend(problems(p, p.read_text(encoding="utf-8")))

    if bad:
        for b in bad:
            print(f"  {b}")
        print(f"\nlint:wrapper: {len(bad)} problem(s)")
        return 1
    print(f"lint:wrapper: clean ({len(WRAPPERS)} wrapper(s))")
    return 0


def selftest() -> int:
    """The exact file that shipped broken must be refused, and the real one must pass."""
    ok = True

    def expect(name: str, text: str, want: str | None) -> None:
        nonlocal ok
        hits = problems(ROOT / "bin/pavois", text)
        if want is None:
            if hits:
                print(f"  FAIL {name}: expected silence, got {hits}")
                ok = False
            else:
                print(f"  ok   {name}: silent, as it must be")
            return
        if any(want in h for h in hits):
            print(f"  ok   {name}: caught")
        else:
            print(f"  FAIL {name}: expected a hit containing {want!r}, got {hits}")
            ok = False

    # Verbatim, the two lines that were on main for a fortnight.
    expect(
        "the wrapper as it actually shipped",
        "#!/bin/sh\n"
        'exec "/tmp/claude-1000/-home-bob-Projets-confkit/abc/scratchpad/wt-go/go/pavois" "$@"\n',
        "execs an absolute path",
    )
    expect(
        "a hardcoded home directory",
        '#!/bin/sh\nbin="/home/bob/Projets/confkit/go/pavois"\nexec "$bin" "$@"\n',
        "machine-specific path",
    )
    expect(
        "no dirname anywhere",
        '#!/bin/sh\nexec ./go/pavois "$@"\n',
        "nothing resolves from the script's own location",
    )
    # The witness: the real wrapper must pass, or the guard is useless.
    expect(
        "the wrapper as it should be",
        '#!/usr/bin/env sh\nset -e\nhere="$(cd "$(dirname "$0")/.." && pwd)"\n'
        'bin="$here/go/pavois"\n( cd "$here/go" && go build -o pavois . )\nexec "$bin" "$@"\n',
        None,
    )
    print("selftest: PASS" if ok else "selftest: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
