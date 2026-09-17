#!/usr/bin/env python3
"""Fail if the binary embeds a directory that the release build never fills.

This is the defect that shipped twice, and the second time nothing local could see it.

`//go:embed all:content` compiles whatever is in that directory at BUILD time. In a checkout the
directory is filled first, by `mise run embed:all`, so every local build, every test and every
guard sees a complete binary. The artifact a user downloads is built by the release workflow, which
fills the directories it was told about. When `go/internal/reference/{content,catalogue,data}` were
added, the workflow was not told, and v0.1.2 shipped a binary that could scan a host and then said

    error: no hardening reference for debian13: this binary embeds none and none is on disk

for `harden plan`, `rules`, `norms` and `oscal`: half the product, unreachable for anyone who
installed from a release. An empty embed is not a build error. Nothing anywhere fails. The binary
is simply smaller and answers that sentence to the first command a user runs.

So the rule is mechanical, needs no build and no network:

    a //go:embed directory that git holds EMPTY (only a .keep) must be named by the release path.

A directory whose contents are committed is fine as it is: what is in git is what gets compiled.
It is the empty ones that depend on a copy step existing, and those are the ones that rot when
someone adds a fourth embed and updates only the task they were looking at.

Usage: python3 tools/lint_embed_release.py [root]     (--selftest proves it bites)
"""

from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

# What the RELEASE actually runs, and nothing else. mise.toml is deliberately absent, and that
# absence is the whole point: at v0.1.2 `mise run embed:reference` named all three directories, so a
# linter that accepted mise.toml as proof passed on the tree that shipped broken. A local task
# filling a directory says nothing about the artifact a user downloads. Only the workflow, and the
# script the workflow runs, count.
RELEASE_PATHS = [
    ".github/workflows/release.yml",
    "tools/release/embed_reference.sh",
]

EMBED = re.compile(r"^\s*//go:embed\s+(.+)$", re.MULTILINE)


def embed_dirs(root: pathlib.Path) -> list[pathlib.Path]:
    """Every directory a //go:embed directive pulls in, as a repo-relative path."""
    found: set[pathlib.Path] = set()
    for go in (root / "go").rglob("*.go"):
        if go.name.endswith("_test.go"):
            continue
        for line in EMBED.findall(go.read_text(encoding="utf-8")):
            for pattern in line.split():
                # `all:content` means the same directory, including files go:embed skips by
                # default (dotfiles, _ prefixes). The prefix does not change WHICH directory.
                target = pattern.split(":", 1)[-1]
                if any(c in target for c in "*?["):
                    continue  # a glob names files, not a directory that can sit empty
                candidate = go.parent / target
                if candidate.is_dir():
                    found.add(candidate.relative_to(root))
    return sorted(found)


def tracked_files(root: pathlib.Path, d: pathlib.Path) -> list[str]:
    """What git holds under a directory. The working tree may be filled by a local embed task."""
    out = subprocess.run(  # noqa: S603
        ["git", "ls-files", "--", str(d)],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
        timeout=20,
    ).stdout
    return [line for line in out.splitlines() if line.strip()]


def copy_sources(root: pathlib.Path) -> list[str]:
    """The source globs embed_reference.sh copies from, read out of its COPIES table."""
    script = root / "tools/release/embed_reference.sh"
    if not script.exists():
        return []
    body = script.read_text(encoding="utf-8")
    table = re.search(r"COPIES=\((.*?)\n\)", body, re.DOTALL)
    if not table:
        return []
    return [m.group(1) for m in re.finditer(r'"([^"|]+)\|[^"]+"', table.group(1))]


def is_generated(root: pathlib.Path, path: pathlib.Path) -> bool:
    """True when git holds nothing at this path: it is produced by a build step, not committed."""
    ignored = subprocess.run(  # noqa: S603
        ["git", "check-ignore", "-q", str(path)],
        cwd=root,
        capture_output=True,
        check=False,
        timeout=20,
    )
    return ignored.returncode == 0


def check(root: pathlib.Path) -> list[str]:
    problems: list[str] = []
    release_text = ""
    for rel in RELEASE_PATHS:
        p = root / rel
        if p.exists():
            release_text += p.read_text(encoding="utf-8")

    # Every SOURCE the copy reads must exist in the release job's checkout. A generated source does
    # not: docs/reference/pavois-content/ is rendered from rules.yml and gitignored, so a copy step
    # that reads it straight out of the checkout fails the release with `nothing matches`. That is
    # better than shipping an empty embed and still a broken release, and it was only visible by
    # running release.yml itself. A generated source has to reach the build job some other way, so
    # the workflow must name it.
    workflow = (root / ".github/workflows/release.yml").read_text(encoding="utf-8")
    # A `path:` value, not a substring of the file. The first version matched anywhere in the
    # workflow, and release.yml explains this very defect in a comment that contains the path, so
    # deleting both artifact steps and keeping the comment produced zero findings: the rule was
    # satisfied by the prose describing what it was meant to prevent.
    restored = {
        m.group(1).strip().rstrip("/")
        for m in re.finditer(r"^\s*path:\s*(\S+)\s*$", workflow, re.MULTILINE)
    }
    for src in copy_sources(root):
        src_dir = pathlib.Path(src).parent if any(c in src for c in "*?[") else pathlib.Path(src)
        if not is_generated(root, src_dir):
            continue
        # The build job checks out into pavois/, so the download path is prefixed there.
        if not any(p == str(src_dir) or p.endswith("/" + str(src_dir)) for p in restored):
            problems.append(
                f"{src_dir}: embed_reference.sh copies from it, git does not hold it (it is\n"
                f"  generated), and no release.yml step restores it to that path. The build job\n"
                f"  checks out the repository, so the copy fails with 'nothing matches {src}'.\n"
                f"  Render it in the release job, or upload it from the job that does and\n"
                f"  download it before the copy."
            )

    dirs = embed_dirs(root)
    if not dirs:
        return [
            "no //go:embed directory found under go/; this linter is looking at the wrong tree "
            "and would pass forever"
        ]

    for d in dirs:
        content = [f for f in tracked_files(root, d) if not f.endswith("/.keep")]
        if content:
            continue  # committed, so a release build compiles it as it stands
        if str(d) not in release_text:
            problems.append(
                f"{d}: embedded by the binary, empty in git, and no release step fills it.\n"
                f"  A build succeeds and ships an empty {d.name}/; the first command that\n"
                f"  reads it answers 'this binary embeds none and none is on disk'.\n"
                f"  Add it to tools/release/embed_reference.sh, which mise and the release\n"
                f"  workflow both run."
            )
    return problems


def selftest(root: pathlib.Path) -> int:
    """Plant the defect in a copy and demand red: a linter that never failed cannot be trusted."""
    print("the embed linter rejects:")
    with tempfile.TemporaryDirectory() as d:
        tree = pathlib.Path(d) / "repo"
        for rel in ["go", "tools/release", ".github/workflows"]:
            (tree / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(root / rel, tree / rel, dirs_exist_ok=True)
        shutil.copy(root / "mise.toml", tree / "mise.toml")
        # .gitignore comes along, and so does the generated source directory: without them
        # `git check-ignore` answers "not ignored" in the copy and the second case below silently
        # tests nothing, reporting a pass it has not earned. A harness has to reproduce the
        # condition it claims to test.
        shutil.copy(root / ".gitignore", tree / ".gitignore")
        (tree / "docs/reference/pavois-content").mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init", "-q"], cwd=tree, check=False, capture_output=True)  # noqa: S603, S607

        # A new embed directory nobody taught the release path about: what actually happened.
        orphan = tree / "go/internal/reference/newthing"
        orphan.mkdir(parents=True)
        (orphan / ".keep").write_text("")
        pkg = tree / "go/internal/reference/reference.go"
        pkg.write_text(
            pkg.read_text().replace("//go:embed all:content", "//go:embed all:newthing", 1)
        )
        subprocess.run(["git", "add", "-A"], cwd=tree, check=False, capture_output=True)  # noqa: S603, S607

        problems = check(tree)
        if any("newthing" in p for p in problems):
            print("  ok   an embed directory no release step fills")
        else:
            print(f"  FAIL the planted orphan embed was not caught\n{problems}")
            return 1

        # And the second half: a copy whose SOURCE the release job will not have. This is the
        # near-miss that act caught, reduced to a rule.
        #
        # Only the `path:` values are removed; every comment mentioning the directory is left in
        # place. That is deliberate, and it is how the first version of this rule was shown to be
        # decorative: it searched the whole workflow for the path, and release.yml explains this
        # exact defect in a comment that contains it, so the prose satisfied the rule.
        wf = tree / ".github/workflows/release.yml"
        wf.write_text(
            re.sub(
                r"^(\s*path:\s*)\S*docs/reference/pavois-content\s*$",
                r"\1docs/reference/elsewhere",
                wf.read_text(),
                flags=re.MULTILINE,
            )
        )
        problems = check(tree)
        if any("nothing matches" in p for p in problems):
            print("  ok   a generated source the release job never receives")
        else:
            print(f"  FAIL the unreachable generated source was not caught\n{problems}")
            return 1

    print("\nand accepts the tree as it stands:")
    problems = check(root)
    if problems:
        print("  FAIL")
        for p in problems:
            print(p)
        return 1
    print("  ok   every embedded directory is either committed or filled by the release path")
    return 0


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--selftest"]
    root = pathlib.Path(args[0]) if args else pathlib.Path(__file__).resolve().parent.parent
    if "--selftest" in sys.argv[1:]:
        return selftest(root)

    problems = check(root)
    if problems:
        for p in problems:
            print(p)
        print(f"\n{len(problems)} embed directory(ies) would ship empty.")
        return 1
    print("embed: every //go:embed directory is committed or filled by the release path")
    return 0


if __name__ == "__main__":
    sys.exit(main())
