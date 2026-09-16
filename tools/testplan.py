#!/usr/bin/env python3
"""What this diff earns you, cheapest first: and what each run does NOT prove.

The problem this solves is not "which tests exist". It is that the expensive, non-negotiable
runs live in prose. CLAUDE.md states that no rules.yml change merges without a REAL scan on
debian12, and that static validation never substitutes for it: and PR #129 was merged on
static validation alone anyway, because the rule lived in a file and not in the tooling.

So: read the diff, print the runs it earns, cheapest first, each with the sentence saying what
it leaves unproven. `--check` (what `mise run prepush` calls) fails on a changed path that no
rule sorts, which is what stops the table below from quietly rotting as the repo grows.

Timings are measured on this repo, not guessed. Anything needing a live target is marked as
such: those can never run in a hook, and pretending otherwise is how a hook gets bypassed.

  mise run testplan                 # what the current branch earns, vs origin/main
  mise run testplan -- --from HEAD  # what the uncommitted working tree earns
  mise run testplan -- --check      # fail on an unsorted path (used by prepush)
"""

from __future__ import annotations

import argparse
import fnmatch
import subprocess
import sys
from dataclasses import dataclass, field

# Cost buckets, ordered. The order is the output order: a contributor should be able to stop
# reading at the point where the budget runs out and still have run the cheapest useful thing.
OFFLINE = 0  # seconds, deterministic, no target: hook material
LOCAL = 1  # tens of seconds to minutes, still no target
TARGET = 2  # needs a live VM: never a hook, always before merge


@dataclass
class Rule:
    """One row of the table: what a path means, and what it earns."""

    label: str
    patterns: list[str]
    runs: list[tuple[int, str, str]] = field(default_factory=list)  # (cost, command, unproven)


# The table. Order matters only for readability; every matching rule contributes its runs.
RULES: list[Rule] = [
    Rule(
        "the rule base (what every target is audited against)",
        ["docs/reference/rules.yml"],
        [
            (
                OFFLINE,
                "mise run gen:verify",
                "that the generated corpus renders: only that it matches",
            ),
            (
                OFFLINE,
                "mise run lint:rules",
                "nothing about a live system: it lints the content, not the verdict",
            ),
            (LOCAL, "mise run render", "that a rendered control actually evaluates on a host"),
            (
                TARGET,
                "pavois scan <debian12-vm> --profile linux/debian12 --sudo --on-target",
                "that the remediation converges: a control can be correct and unfixable",
            ),
            (
                TARGET,
                "mise run regression -- <scan.json> --os debian12",
                "anything about the other 8 OSes; debian12 is the frozen baseline, not the corpus",
            ),
        ],
    ),
    Rule(
        "the OS primitives (one wrong cell breaks one control on every OS that uses it)",
        ["docs/reference/os/*"],
        [
            (
                OFFLINE,
                "mise run gen:verify",
                "that a primitive is TRUE: only that the render is in sync",
            ),
            (
                LOCAL,
                "apt-cache policy <pkg> / rpm -q <pkg> on the OS you touched",
                "nothing: a primitive is a claim about a distro, only that distro confirms it",
            ),
            (
                TARGET,
                "pavois scan <vm of that OS> --sudo",
                "the other OSes sharing the same primitive key",
            ),
        ],
    ),
    Rule(
        "a regression baseline (you are editing the judge, not the code)",
        ["docs/reference/baselines/*"],
        [
            (
                TARGET,
                "the scan that PRODUCED it: mise run regression -- <scan.json> --os <os> --update",
                "that the new baseline is better: one edited by hand proves only it was edited",
            ),
        ],
    ),
    Rule(
        "the bilingual prose behind the rule pages",
        ["docs/reference/prose/*"],
        [
            (LOCAL, "mise run site:verify", "that FR and EN say the same thing"),
        ],
    ),
    Rule(
        "a remediation (what harden apply will write)",
        [
            "docs/reference/audit.rules",
            "docs/reference/kernel-build/*",
            "docs/reference/kernel-build.sh",
            "docs/reference/partition-build/*",
            "docs/reference/behavioral-probes.yml",
            "docs/reference/exclusivity.yml",
        ],
        [
            (
                TARGET,
                "pavois harden plan <vm> && pavois harden apply <plan> --scan",
                "that it is idempotent or survives a reboot: converge twice and reboot to know",
            ),
        ],
    ),
    Rule(
        "the Go binary",
        ["go/**"],
        [
            (OFFLINE, "mise run test", "any behaviour against a live target"),
            (OFFLINE, "mise run lint", "correctness: it proves style and known-bad patterns only"),
            (
                LOCAL,
                "mise run fuzz  (only if a parser moved: audit/, rollback recipe)",
                "that the inputs it was fed resemble what a real scan produces",
            ),
        ],
    ),
    Rule(
        "the rendered InSpec corpus (GENERATED: edit docs/reference/rules.yml instead)",
        ["profiles/**"],
        [
            (
                OFFLINE,
                "mise run gen:verify",
                "that a hand edit here survives the next `mise run render`: it will not",
            ),
            (
                TARGET,
                "mise run rule:test -- <vm> --sudo --controls <id>",
                "that the other controls of the same domain still pass",
            ),
        ],
    ),
    Rule(
        "the anonymized fixtures behind the published sample report",
        ["docs/examples/*"],
        [
            (
                LOCAL,
                "mise run gen:example",
                "that the fixture is leak-free: re-read it: it ships on the public site",
            ),
        ],
    ),
    Rule(
        "the site (content, pages, styles)",
        ["site/**", "tools/generate_rule_pages.py", "tools/verify_site_content.py"],
        [
            (
                LOCAL,
                "mise run site:verify",
                "that the page renders: only that content and rule base agree",
            ),
            (
                LOCAL,
                "mise run site:build && mise run site:links",
                "that the live site serves it (see #210)",
            ),
            (
                LOCAL,
                "mise run site:validate-seo",
                "ranking; it validates structured data, nothing more",
            ),
            (
                LOCAL,
                "mise run site:validate-hreflang",
                "that an engine honours the annotation: only that it is well-formed and reciprocal",
            ),
        ],
    ),
    Rule(
        "the bilingual handbook",
        ["site/src/content/handbook/**"],
        [
            (
                OFFLINE,
                "mise run validate:i18n",
                "that the FR and EN say the same thing: only that they have the same shape",
            ),
        ],
    ),
    Rule(
        "norm mappings and standards data",
        [
            "docs/reference/norms.yml",
            "docs/reference/baseline.yml",
            "docs/reference/pavois-content/**",
        ],
        [
            (
                OFFLINE,
                "mise run validate:mappings",
                "that a mapping is the RIGHT one: only that the ref exists upstream",
            ),
            (
                LOCAL,
                "mise run oscal",
                "that a consumer can ingest it; validate against the NIST schema for that",
            ),
        ],
    ),
    Rule(
        "the offline tooling",
        ["tools/**", "pyproject.toml"],
        [
            (
                OFFLINE,
                "pre-commit run --all-files  (ruff, bandit)",
                "that the tool does what its name says",
            ),
        ],
    ),
    Rule(
        "CI workflows and supply-chain config",
        [
            ".github/**",
            ".plumber.yaml",
            ".pre-commit-config.yaml",
            ".trufflehog-lab.yaml",
            ".poutine.yml",
            ".golangci.yml",
            "osv-scanner.toml",
        ],
        [
            (
                OFFLINE,
                "actionlint + zizmor + poutine  (see #215)",
                "that the job runs green: only that it is well-formed",
            ),
        ],
    ),
    Rule(
        "the operator-facing wrapper and example files",
        ["bin/pavois", "docs/reference/*.example", "docs/reference/scanner-account.md"],
        [
            (
                OFFLINE,
                "run it: bin/pavois version",
                "that it builds on a machine other than yours; it compiles on demand",
            ),
        ],
    ),
    Rule(
        "the toolchain and task definitions",
        ["mise.toml", "go/go.mod", "go/go.sum"],
        [
            (
                OFFLINE,
                "mise run prepush",
                "that CI agrees: CI resolves `go-version: 1.26` to the latest patch",
            ),
        ],
    ),
    Rule(
        "packaging and release plumbing",
        ["nfpm.yaml", ".goreleaser*", "Dockerfile"],
        [
            (
                LOCAL,
                "mise run release:check -- vX.Y.Z  (see #211)",
                "that the published artefact verifies: download it and check",
            ),
        ],
    ),
    # Deliberate no-ops: paths that genuinely earn nothing beyond the hook. Listing them is what
    # keeps --check honest: silence would be indistinguishable from a forgotten rule.
    Rule(
        "documentation and repo metadata (nothing beyond the hook)",
        [
            "*.md",
            "docs/*.md",
            "docs/**/*.md",
            "LICENSE",
            "NOTICE",
            "THIRD_PARTY.md",
            ".gitignore",
            ".editorconfig",
            "media/**",
            "maquettes/**",
        ],
    ),
    Rule(
        "local artefacts, never pushed (nothing to run)",
        ["reports/**", "restore-points/**", "hardening-plan-*.yml", "targets/**", "test-vms/**"],
    ),
]


def changed_paths(base: str) -> list[str]:
    """Paths this branch changes vs `base`, plus anything uncommitted in the tree."""

    def git(*args: str) -> list[str]:
        out = subprocess.run(["git", *args], capture_output=True, text=True, check=False)
        return [ln for ln in out.stdout.splitlines() if ln.strip()]

    paths: set[str] = set()
    if base != "HEAD":
        merge_base = subprocess.run(
            ["git", "merge-base", base, "HEAD"], capture_output=True, text=True, check=False
        ).stdout.strip()
        if merge_base:
            paths.update(git("diff", "--name-only", merge_base, "HEAD"))
    paths.update(git("diff", "--name-only", "HEAD"))  # unstaged
    paths.update(git("diff", "--name-only", "--cached"))  # staged
    # Untracked files are deliberately out: nothing pushes them, so a hook that failed on one
    # would fail on a scratch file. `git add` is what makes a new file part of the plan.
    return sorted(paths)


def default_base() -> str:
    """The branch point to diff against: origin/main, else main, else the working tree alone."""
    for ref in ("origin/main", "main"):
        if (
            subprocess.run(
                ["git", "rev-parse", "--verify", ref], capture_output=True, check=False
            ).returncode
            == 0
        ):
            return ref
    return "HEAD"


def matches(path: str, patterns: list[str]) -> bool:
    for pat in patterns:
        # fnmatch does not treat "/" specially, so "go/**" matches "go/cmd/x.go" as written.
        if fnmatch.fnmatch(path, pat) or fnmatch.fnmatch(path, pat.rstrip("*") + "*"):
            return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description="What this diff earns, cheapest first.")
    ap.add_argument(
        "--from", dest="base", default=None, help="diff base (default: origin/main, else main)"
    )
    ap.add_argument("--check", action="store_true", help="exit 1 on a changed path no rule sorts")
    args = ap.parse_args()

    base = args.base or default_base()
    paths = changed_paths(base)
    if not paths:
        print(f"testplan: nothing changed vs {base}.")
        return 0

    matched: list[Rule] = []
    unsorted_paths: list[str] = []
    for path in paths:
        hit = [r for r in RULES if matches(path, r.patterns)]
        if not hit:
            unsorted_paths.append(path)
            continue
        for rule in hit:
            if rule not in matched:
                matched.append(rule)

    print(f"testplan: {len(paths)} path(s) changed vs {base}\n")
    for rule in matched:
        print(f"  ▸ {rule.label}")
        if not rule.runs:
            print("      nothing beyond the pre-push gate.\n")
            continue
        for cost, cmd, unproven in sorted(rule.runs, key=lambda r: r[0]):
            tag = {OFFLINE: "offline", LOCAL: "local ", TARGET: "TARGET"}[cost]
            print(f"      [{tag}] {cmd}")
            print(f"               does not prove: {unproven}")
        print()

    if any(cost == TARGET for r in matched for cost, _, _ in r.runs):
        print("  ⚠ This diff touches what a target is audited against or how it is remediated.")
        print("    CLAUDE.md: no such change merges without a REAL scan on debian12.")
        print("    Static validation is not a substitute, and a green prepush is not a scan.\n")

    if unsorted_paths:
        print("  ✗ No rule sorts these paths: add one to tools/testplan.py:")
        for path in unsorted_paths:
            print(f"      {path}")
        print("    A path nobody classified is a path nobody knows how to test.")
        return 1 if args.check else 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
