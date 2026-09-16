#!/usr/bin/env python3
"""Read EVERY commit for secrets and lab topology, not just what a push adds.

The pre-commit hooks and the range-based CI job both scan a diff. Nothing had ever re-read the
commits that predate them, and that is the question that matters before a repository goes public:
publishing ships the whole history, not the tip.

Two passes, blind to different things:

1. built-in detectors   ~800 credential shapes (cloud keys, platform tokens, private keys)
2. lab detectors        private IPs, internal hostnames, a literal lab password. Not credentials,
                        so pass 1 ignores them by design, and they are exactly what must not ship.

``--no-verification`` keeps every candidate on this machine. A scan must never hand a possible
credential to a third-party API just to find out what it is.

Findings already known and judged acceptable live in ``.trufflehog-baseline.tsv``, one per line with
the reason. That file is a LEDGER OF DEBT, not an absolution: anything in it is still in the
history, and still ships when the repo is published. Anything NOT in it fails the run.

    tools/scan_history_secrets.py             # fail on anything new
    tools/scan_history_secrets.py --list      # print every finding, baseline included
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()
)
BASELINE = ROOT / ".trufflehog-baseline.tsv"

# BingSubscriptionKey: the site carries a Bing Webmaster Tools OWNERSHIP token, a 32-hex string with
# the exact shape of a Bing API subscription key. It is public by construction, served in the <head>
# of every page; it proves control of the site and grants no access. Left in, it would be reported
# on every run forever, which is how a team learns to ignore a scanner.
EXCLUDED_DETECTORS = "BingSubscriptionKey"


def repo_url() -> str:
    """TruffleHog reads .git as a directory, which a worktree's .git file is not."""
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    return f"file://{Path(common).parent}"


def scan(extra: list[str]) -> list[dict]:
    cmd = [
        "trufflehog",
        "git",
        repo_url(),
        "--results=verified,unverified,unknown",
        "--no-verification",
        "--json",
        "--no-update",
        *extra,
    ]
    out = subprocess.run(cmd, capture_output=True, text=True)
    findings = []
    for line in out.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            findings.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return findings


def fingerprint(f: dict) -> str:
    """Identify a finding by WHERE it is, never by its value: a fingerprint file must be safe to
    commit. Commit + file + line is stable as long as history is not rewritten, and rewriting
    history is precisely the operation that would remove the finding anyway."""
    git = (f.get("SourceMetadata") or {}).get("Data", {}).get("Git", {}) or {}
    return "\t".join(
        [
            f.get("DetectorName", "?"),
            (git.get("commit") or "?")[:12],
            git.get("file") or "?",
            str(git.get("line") or "?"),
        ]
    )


def load_baseline() -> dict[str, str]:
    known: dict[str, str] = {}
    if not BASELINE.exists():
        return known
    for raw in BASELINE.read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        parts = raw.rstrip("\n").split("\t")
        if len(parts) < 5:
            continue
        known["\t".join(parts[:4])] = parts[4]
    return known


def main() -> int:
    list_only = "--list" in sys.argv

    findings = scan([f"--exclude-detectors={EXCLUDED_DETECTORS}"])
    findings += scan(["--config=.trufflehog-lab.yaml", "--include-detectors=CustomRegex"])

    baseline = load_baseline()
    total = subprocess.run(
        ["git", "rev-list", "--all", "--count"], capture_output=True, text=True, check=True
    ).stdout.strip()

    known, new = [], []
    for f in findings:
        fp = fingerprint(f)
        (known if fp in baseline else new).append((fp, f))

    if list_only:
        for fp in sorted(fp for fp, _ in known):
            print(f"  baseline  {fp}\t{baseline[fp]}")
        for fp in sorted(fp for fp, _ in new):
            print(f"  NEW       {fp}")

    print(f"history: {total} commit(s) scanned, {len(known)} known, {len(new)} new")

    if new:
        print()
        print("NEW FINDINGS. Read them before publishing anything:")
        for fp in sorted(fp for fp, _ in new):
            det, commit, path, line = fp.split("\t")
            print(f"  {det:<20} {commit}  {path}:{line}")
        print()
        print("Removing it from HEAD is not enough: the commit still carries it. Either rewrite")
        print("history, or add the line to .trufflehog-baseline.tsv WITH a reason, which records")
        print("that it ships.")
        return 1

    if known:
        print(
            f"note: {len(known)} accepted finding(s) still ship with the history, "
            f"see {BASELINE.name}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
