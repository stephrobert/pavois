#!/usr/bin/env python3
"""Prove the install-docs linter fails when it should.

A linter that has never rejected anything is indistinguishable from a linter that cannot. This one
exists precisely because a comment in install.ts claimed a guard that did not exist, so the guard
gets checked the same way a control does: by making it fail on purpose.

Each case plants one defect in a COPY of the tree and asserts the linter catches it, then
asserts the untouched tree passes. Run: python3 tools/lint_install_docs_test.py
"""

from __future__ import annotations

import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
LINTER = pathlib.Path(__file__).resolve().parent / "lint_install_docs.py"

PAGE = "site/src/pages/[lang]/installation.astro"
SOURCE = "site/src/data/install.ts"


def run(tree: pathlib.Path) -> tuple[int, str]:
    p = subprocess.run(
        [sys.executable, str(tree / "tools/lint_install_docs.py")],
        capture_output=True,
        text=True,
    )
    return p.returncode, p.stdout + p.stderr


def planted(mutate) -> tuple[int, str]:
    """Copy the two directories the linter reads, apply one defect, run it there."""
    with tempfile.TemporaryDirectory() as d:
        tree = pathlib.Path(d) / "repo"
        (tree / "tools").mkdir(parents=True)
        shutil.copy(LINTER, tree / "tools/lint_install_docs.py")
        shutil.copytree(ROOT / "site/src/pages", tree / "site/src/pages")
        (tree / "site/src/data").mkdir(parents=True)
        shutil.copy(ROOT / SOURCE, tree / SOURCE)
        # A git repository carrying the real newest release tag. Without it `newest_tag()` returns
        # nothing and the version check SKIPS, so the planted stale version was never examined and
        # the case reported a pass it had not earned. The harness has to reproduce the condition it
        # claims to test.
        subprocess.run(["git", "init", "-q"], cwd=tree, check=False, capture_output=True)
        subprocess.run(
            ["git", "commit", "-q", "--allow-empty", "-m", "base"],
            cwd=tree,
            check=False,
            capture_output=True,
        )
        if tag := _newest_release_tag():
            subprocess.run(["git", "tag", tag], cwd=tree, check=False, capture_output=True)
        mutate(tree)
        return run(tree)


def _newest_release_tag() -> str:
    """The repository's newest vX.Y.Z, so the copy can carry the same one."""
    out = subprocess.run(
        ["git", "tag", "--list", "v[0-9]*", "--sort=-v:refname"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    for line in out.splitlines():
        if re.match(r"^v\d+\.\d+\.\d+$", line.strip()):
            return line.strip()
    return ""


def main() -> int:
    failures = 0

    def check(name: str, rc: int, out: str, want: str) -> None:
        nonlocal failures
        if rc != 0 and want in out:
            print(f"  ok   {name}")
        else:
            failures += 1
            print(f"  FAIL {name}: rc={rc}, wanted {want!r} in output\n{out}")

    print("the linter rejects:")

    # 1. A page that retypes a command instead of rendering the block.
    def retype(tree: pathlib.Path) -> None:
        p = tree / PAGE
        p.write_text(p.read_text() + "\n<pre>sudo install -m 0755 pavois /usr/local/bin/</pre>\n")

    rc, out = planted(retype)
    check("a page that retypes an install command", rc, out, "retypes an install command")

    # 2. A page that pipes a downloaded URL into a shell.
    def pipe(tree: pathlib.Path) -> None:
        p = tree / PAGE
        p.write_text(p.read_text() + "\n<pre>curl -L https://example.com/i.sh | sudo bash</pre>\n")

    rc, out = planted(pipe)
    check("a page that pipes a download into a shell", rc, out, "pipes a download into a shell")

    # 3. A page rendering a block that install.ts does not export.
    def ghost(tree: pathlib.Path) -> None:
        p = tree / PAGE
        p.write_text(p.read_text() + "\n{highlight(install.notABlock.code(fr), 'bash')}\n")

    rc, out = planted(ghost)
    check("a page rendering a block that does not exist", rc, out, "does not export")

    # 4. A guarded command that has disappeared from the source: the rule would still pass while
    #    protecting nothing, which is the failure mode this whole file exists to rule out.
    def stale(tree: pathlib.Path) -> None:
        p = tree / SOURCE
        p.write_text(p.read_text().replace("gh attestation verify", "gh att-verify"))

    # 5. One entry page that stops telling a first-run reader about the engine. This is the defect
    #    that was actually there: the installation page listed its prerequisites without the engine
    #    while the get-started page named it, so which reader got told depended on which page they
    #    opened.
    def half_told(tree: pathlib.Path) -> None:
        p = tree / PAGE
        p.write_text(p.read_text().replace("no native CINC engine found", "an error occurs"))

    rc, out = planted(half_told)
    check("an entry page that drops a first-run claim", rc, out, "both entry pages must")

    # 6. A site still handing out the previous release. This is the defect that actually happened,
    #    twice: after v0.1.1 shipped the site offered the v0.1.0 artifacts, which could not resolve
    #    a profile on any machine, and after v0.1.2 it offered v0.1.1. A reader downloads the
    #    version this constant names, not the one that was tagged.
    def stale_version(tree: pathlib.Path) -> None:
        p = tree / SOURCE
        s = p.read_text()
        cur = re.search(r"export const VERSION = '(v[^']+)'", s)
        if not cur:
            # Not an assert: bandit refuses those, and rightly, since -O strips them and the
            # check would vanish from an optimised run.
            raise RuntimeError("no VERSION constant in install.ts to age")
        # Aged relative to the newest TAG, not to the constant. The rule is "the site is behind the
        # newest release", so during release prep the constant is legitimately AHEAD of the tag and
        # decrementing it produced a version that is not stale at all: the case then tested nothing
        # and reported a pass it had not earned.
        base = _newest_release_tag() or cur.group(1)
        major, minor, patch = (int(x) for x in base[1:].split("-")[0].split("."))
        old = f"v{major}.{minor}.{max(patch - 1, 0)}"
        p.write_text(s.replace(cur.group(0), f"export const VERSION = '{old}'", 1))

    rc, out = planted(stale_version)
    check("a site still handing out the previous release", rc, out, "the newest tag is")

    rc, out = planted(stale)
    check("a fragment that no longer exists in the source", rc, out, "guards nothing")

    print("\nthe linter accepts the tree as it stands:")
    rc, out = run(ROOT)
    if rc == 0:
        print("  ok   no problem reported")
    else:
        failures += 1
        print(f"  FAIL rc={rc}\n{out}")

    if failures:
        print(f"\n{failures} case(s) wrong: the linter does not measure what it claims.")
        return 1
    print("\nthe linter fails when it should, and only then.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
