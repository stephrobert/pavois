#!/usr/bin/env python3
"""Fail if a page grows its own copy of an install command.

site/src/data/install.ts exists because the install instructions used to live in three places and
drifted, as duplicated instructions always do: the get-started page led with a build from source and
claimed no release existed, while the installation page led with a binary; one told the reader to
pipe a script into a shell while the other said, correctly, that a hardening tool whose first line is
`curl | sh` has already lost the argument.

install.ts said this linter enforced that. It did not exist. A comment claiming a guard that is not
there is worse than no comment: it is the reason nobody looks.

Two rules, and only two, because a linter nobody trusts gets deleted:

  1. A page under site/src/pages must not retype an install command. If a distinctive command
     fragment appears in a page outside an `install.<block>.code(fr)` call, it has been copied.
     Prose that MENTIONS a tool is fine; it is shell that is forbidden.

  2. Nothing that a reader is told to run may pipe a download into a shell. The site states that
     rule about itself, so the rule is checked rather than trusted. The exception is code that
     DISPLAYS what an opt-in flag would run (engine.go, harden.go): showing the command you are
     refusing to run is the opposite of asking for it, and those live in Go, not in a page.

Usage: python3 tools/lint_install_docs.py        (exit 1 on the first rule broken)
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGES = ROOT / "site/src/pages"
SOURCE = ROOT / "site/src/data/install.ts"

# Fragments of shell that belong to an install block and nowhere else. Each is distinctive enough
# that its presence in a page means the command was retyped, not referenced.
COMMANDS = [
    "sha256sum --ignore-missing --check",
    "sha256sum --check",
    "install -m 0755",
    "gh release download",
    "gh attestation verify",
    "extrepo enable mise",
    "dpkg -i pavois",
    "rpm -i pavois",
    "omnitruck.cinc.sh/stable",
]

# A download piped straight into an interpreter. Two deliberate exclusions:
#
#   - `curl ... -o file && sh file` does not match: downloading to a file is what lets a reader look
#     at it before it runs, which is the whole distinction the site draws.
#   - a URL is required between the fetch and the pipe. Both pages say, in prose, that Pavois will
#     never ask you to `curl | sh`; a rule that flags the sentence stating the rule is a rule that
#     gets switched off. What is dangerous is a fetched URL reaching a shell, so that is what is
#     matched.
PIPE_TO_SHELL = re.compile(r"(?:curl|wget)[^\n|]*https?://[^\n|]*\|\s*(?:sudo\s+)?(?:ba)?sh\b")

# The shape a page uses to RENDER a block: install.binaryCurl.code(fr). A page may name blocks
# freely; what it may not do is inline their contents.
RENDERS = re.compile(r"install\.(\w+)\.code\(")


def fail(problems: list[str]) -> int:
    for p in problems:
        print(p)
    print(f"\n{len(problems)} problem(s). The install commands live in site/src/data/install.ts;")
    print("a page renders them with <Fragment set:html={highlight(install.<block>.code(fr), 'bash')} />.")
    return 1


def main() -> int:
    if not SOURCE.exists():
        print(f"missing {SOURCE.relative_to(ROOT)}: the single source of the install commands")
        return 1

    problems: list[str] = []
    source_text = SOURCE.read_text(encoding="utf-8")

    # Every command this linter guards must actually appear in the source, or the fragment has gone
    # stale and the rule silently stops protecting anything.
    for cmd in COMMANDS:
        if cmd not in source_text:
            problems.append(
                f"{SOURCE.relative_to(ROOT)}: no block contains {cmd!r};\n"
                f"  this linter is guarding a command that no longer exists, so it guards nothing"
            )

    for page in sorted(PAGES.rglob("*.astro")):
        text = page.read_text(encoding="utf-8")
        rel = page.relative_to(ROOT)

        for cmd in COMMANDS:
            if cmd in text:
                problems.append(
                    f"{rel}: retypes an install command, {cmd!r}\n"
                    f"  render the block instead: install.<block>.code(fr)"
                )

        for m in PIPE_TO_SHELL.finditer(text):
            line = text[: m.start()].count("\n") + 1
            problems.append(
                f"{rel}:{line}: pipes a download into a shell, {m.group(0).strip()!r}\n"
                f"  download to a file and check its sum; this site says it never asks for this"
            )

    # The blocks a page claims to render must exist. A renamed block leaves a page rendering
    # `undefined`, which Astro turns into an empty code frame rather than an error.
    exported = set(re.findall(r"export const (\w+): Block", source_text))
    for page in sorted(PAGES.rglob("*.astro")):
        for name in RENDERS.findall(page.read_text(encoding="utf-8")):
            if name not in exported:
                problems.append(
                    f"{page.relative_to(ROOT)}: renders install.{name}, which install.ts does not export\n"
                    f"  known blocks: {', '.join(sorted(exported))}"
                )

    if problems:
        return fail(problems)
    print("install docs: one source, no page retypes a command, nothing is piped into a shell")
    return 0


if __name__ == "__main__":
    sys.exit(main())
