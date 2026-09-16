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
        mutate(tree)
        return run(tree)


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
