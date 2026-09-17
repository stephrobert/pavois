#!/usr/bin/env python3
"""Fail if a page grows its own copy of an install command.

site/src/data/install.ts exists because the install instructions used to live in three places and
drifted, as duplicated instructions always do: the get-started page led with a build from source and
claimed no release existed, while the installation page led with a binary; one told the reader to
pipe a script into a shell while the other said, correctly, that a hardening tool whose first
line is `curl | sh` has already lost the argument.

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

# The two pages a new user opens. They are edited at different times for different requests, which
# is exactly how one ends up complete and the other half-done: the installation page once listed
# its prerequisites without the scan engine, while telling the reader that curl "is the whole
# dependency list". The get-started page said it. A reader who opened the other one was not told.
#
# Each claim is (label, any-of-these-strings). One entry per thing a first-run user must be told
# before their first scan fails.
ENTRY_PAGES = [
    "site/src/pages/[lang]/installation.astro",
    "site/src/pages/[lang]/start.astro",
]
ENTRY_CLAIMS = [
    ("the scan engine is named", ["CINC Auditor"]),
    (
        "no package manager can fetch it",
        ["no distribution repository", "aucun dépôt de distribution"],
    ),
    ("the exact error a user meets", ["no native CINC engine found"]),
    ("the verified install command is rendered", ["install.engineInstall.code"]),
    ("a link to the engine section", ["installation/#engine"]),
]


# The release the site hands out. It is one constant, bumped by hand at each release, and it was
# forgotten twice: after v0.1.1 the site still offered the v0.1.0 artifacts, which could not resolve
# a profile on any machine, and after v0.1.2 it still offered v0.1.1. A reader following the install
# page downloads the version this says, not the one that was tagged.
#
# The check has no network: it compares the constant to the newest tag in the repository, which is
# what a release creates. A tag that does not exist yet (the constant bumped before the tag) is not
# flagged, since that is the order the release process asks for.
def newest_tag() -> str:
    import subprocess  # noqa: PLC0415 - only needed here, and only in a checkout

    try:
        out = subprocess.run(  # noqa: S603
            ["git", "tag", "--list", "v[0-9]*", "--sort=-v:refname"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
    # RELEASE tags only. `--sort=-v:refname` ranked `v0.9.0-clean-room` above `v0.1.2`, and this
    # repository genuinely carries lab tags: a check that compares against one would demand the site
    # advertise a release that was never published. Same shape the preflight enforces on a tag.
    release = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+(-(rc|beta|alpha)\.[0-9]+)?$")
    for line in out.splitlines():
        if release.match(line.strip()):
            return line.strip()
    return ""


def fail(problems: list[str]) -> int:
    for p in problems:
        print(p)
    print(f"\n{len(problems)} problem(s). The install commands live in site/src/data/install.ts;")
    print("a page renders them with")
    print("  <Fragment set:html={highlight(install.<block>.code(fr), 'bash')} />")
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
                    f"{page.relative_to(ROOT)}: renders install.{name}, which install.ts\n"
                    f"  does not export\n"
                    f"  known blocks: {', '.join(sorted(exported))}"
                )

    # The version the site hands out must be the one that was released. Forgotten twice: the site
    # offered v0.1.0 after v0.1.1 shipped, and v0.1.1 after v0.1.2. Nothing caught either, because
    # nothing was looking.
    m = re.search(r"export const VERSION = '(v[^']+)'", source_text)
    tag = newest_tag() if m else ""
    if not m:
        problems.append(
            f"{SOURCE.relative_to(ROOT)}: no VERSION constant; the install links carry no version"
        )
    elif tag and m.group(1) != tag:
        rel = SOURCE.relative_to(ROOT)
        problems.append(
            f"{rel}: the site hands out {m.group(1)}, the newest tag is {tag}\n"
            f"  a reader following the install page downloads the version this names.\n"
            f"  Bump it, or tag {m.group(1)} if that is the release being prepared."
        )

    # The two entry points must tell the same story. A claim that only one of them carries is a
    # claim half the readers never see, and which of the two they opened is not something the
    # project gets to choose.
    for rel in ENTRY_PAGES:
        page = ROOT / rel
        if not page.exists():
            problems.append(f"{rel}: entry page missing; update ENTRY_PAGES if it was renamed")
            continue
        text = page.read_text(encoding="utf-8")
        for label, needles in ENTRY_CLAIMS:
            if not any(n in text for n in needles):
                problems.append(
                    f"{rel}: does not say {label}\n"
                    f"  both entry pages must: a reader does not choose which one they land on"
                )

    if problems:
        return fail(problems)
    print("install docs: one source, no page retypes a command, nothing is piped into a shell,")
    print("  and both entry points tell the same story about the scan engine")
    return 0


if __name__ == "__main__":
    sys.exit(main())
