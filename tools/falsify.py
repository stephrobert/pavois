#!/usr/bin/env python3
"""Replay the declared falsifications: prove each guarded test still BITES today.

A passing test suite is evidence that nothing is broken. It is not evidence that anything is
guarded: a test can quietly stop biting when a refactor moves an assertion, a helper starts
returning early, or a case becomes unreachable. The only proof is to remove the guard and watch
the test go red, and the only proof that survives is the one replayed rather than remembered.

Every verdict here is taken on a COPY of the module, never on the working tree.

The harness refuses a verdict it cannot trust. A mutation that stops the mutant compiling makes
every test fail, which is indistinguishable from the guard being proven: so a mutant that does
not build is reported as VOID, not as a pass. That failure mode is the reason this is a harness
and not a shell loop.

  mise run falsify                 # replay all of tools/falsify.yml
  mise run falsify -- <name>       # one, by name
  mise run falsify -- --selftest   # prove the harness: a no-op mutation must NOT go red
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "tools" / "falsify.yml"

GREEN, RED, DIM, OFF = "\033[32m", "\033[31m", "\033[2m", "\033[0m"
if not sys.stdout.isatty():
    GREEN = RED = DIM = OFF = ""


@dataclass
class Verdict:
    name: str
    ok: bool
    detail: str


def copy_module(dest: Path) -> Path:
    """Copy the Go module into `dest`, minus build output and caches."""
    ignore = shutil.ignore_patterns("pavois", "*.test", ".git", "testdata_tmp")
    shutil.copytree(ROOT / "go", dest / "go", ignore=ignore, symlinks=True)
    return dest / "go"


def run(cmd: list[str], cwd: Path) -> tuple[int, str]:
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)
    return p.returncode, (p.stdout + p.stderr)


def falsify(entry: dict, *, selftest: bool = False) -> Verdict:
    """Apply one mutation to a throwaway copy and demand that its test goes red."""
    name = entry["name"]
    rel = entry["file"]
    find, replace = entry["find"], entry["replace"]
    want = int(entry.get("occurrences", 1))
    if selftest:  # the control case: change nothing, the test must STAY green
        replace = find

    with tempfile.TemporaryDirectory(prefix="pavois-falsify-") as tmp:
        mod = copy_module(Path(tmp))
        target = Path(tmp) / rel
        if not target.exists():
            return Verdict(name, False, f"file not found: {rel} (the declaration has rotted)")

        src = target.read_text()
        found = src.count(find)
        if found != want:
            return Verdict(
                name,
                False,
                f"pattern occurs {found}x in {rel}, declared {want}x: the code moved, "
                "so this falsification no longer measures what it claims",
            )
        target.write_text(src.replace(find, replace))

        rc, out = run(["go", "build", "./..."], mod)
        if rc != 0:
            return Verdict(
                name,
                False,
                "VOID: the mutant does not compile, so a red test would prove nothing.\n"
                f"      {out.strip().splitlines()[0] if out.strip() else ''}\n"
                "      Rewrite the mutation to neuter the logic while keeping every symbol used.",
            )

        rc, out = run(["go", "test", "-run", f"^{entry['test']}$", entry["package"]], mod)
        if selftest:
            if rc == 0:
                return Verdict(
                    name, True, "unmutated tree stays green (harness is not crying wolf)"
                )
            return Verdict(
                name,
                False,
                f"the UNMUTATED tree fails {entry['test']}: the harness or the test\n"
                f"      is broken:\n{out.strip()[:400]}",
            )
        if rc == 0:
            return Verdict(
                name,
                False,
                f"{entry['test']} STILL PASSES with the guard removed: it does not test it.\n"
                f"      guard: {entry['why'].strip()}",
            )
        return Verdict(name, True, f"{entry['test']} goes red without the guard")


def main() -> int:
    ap = argparse.ArgumentParser(description="Replay the declared falsifications.")
    ap.add_argument("name", nargs="?", help="run only this falsification")
    ap.add_argument(
        "--selftest", action="store_true", help="prove the harness on an unmutated tree"
    )
    args = ap.parse_args()

    spec = yaml.safe_load(SPEC.read_text())
    entries = spec["falsifications"]
    if args.name:
        entries = [e for e in entries if e["name"] == args.name]
        if not entries:
            print(f"falsify: no such falsification: {args.name}", file=sys.stderr)
            return 2

    mode = "selftest (nothing mutated: every test must stay GREEN)" if args.selftest else "replay"
    print(f"falsify: {mode}, {len(entries)} declaration(s)\n")

    verdicts = [falsify(e, selftest=args.selftest) for e in entries]
    for v in verdicts:
        mark = f"{GREEN}✔{OFF}" if v.ok else f"{RED}✘{OFF}"
        print(f"  {mark} {v.name}")
        print(f"      {DIM}{v.detail}{OFF}")

    bad = [v for v in verdicts if not v.ok]
    print()
    if bad:
        if args.selftest:
            print(
                f"{RED}falsify: the harness is unsound: "
                f"{len(bad)} declaration(s) fail unmutated.{OFF}"
            )
            print(
                "  Fix this before believing any replay: a harness that cries wolf proves nothing."
            )
        else:
            print(f"{RED}falsify: {len(bad)} of {len(verdicts)} guard(s) not proven.{OFF}")
            print("  A guard whose test does not fail without it is a guard in name only.")
        return 1
    if args.selftest:
        print(
            f"{GREEN}falsify: harness sound: {len(verdicts)} declaration(s) green unmutated.{OFF}"
        )
        print("  This says nothing about the guards themselves: run `mise run falsify` for that.")
        return 0
    print(f"{GREEN}falsify: {len(verdicts)} guard(s) proven to bite today.{OFF}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
