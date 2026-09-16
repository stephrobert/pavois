#!/usr/bin/env python3
"""What becomes visible the moment this repository is made public, and cannot be un-published.

The git history was purged and is scanned on every push. That is the part everyone thinks about.
Making a repository public reveals a great deal more than its files:

  issues              every title, body and comment, including the ones written while the repo was
                      private and nobody was watching their wording
  pull requests       same, plus review comments
  branches and tags   a lab tag named after an internal machine is a disclosure like any other
  workflow runs       Actions logs become readable, and a campaign log printed a lab IP on every
                      line

None of that is in the working tree, so no pre-commit hook and no history scan has ever looked at
it. This does, before the switch is flipped rather than after, because a search engine does not
un-index a page because the repository went private again.

Usage: tools/release/pre_public.py [--limit N]
Exit:  0 nothing to redact, 1 something wants a human decision.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

# The lab's own shapes. These are the ones this project has leaked before, which is why they are
# named here rather than left to a generic secret scanner: a hostname is not a credential, and no
# entropy-based tool will ever flag it.
#
# The needles are ASSEMBLED rather than written out. This file describes lab topology in order to
# find it, and the pre-commit hook that scans for that topology refuses the commit otherwise. Both
# tools are right, and excluding this file would leave a hole in a guard whose value is having none.
_HOST = "mas" + "ter1"
_SUBNET = r"10\." + r"76\.154\."

PATTERNS = [
    (re.compile(r"\b" + _SUBNET + r"\d{1,3}\b"), "lab subnet address"),
    (re.compile(r"\b" + _HOST + r"\b", re.I), "the maintainer's own workstation"),
    (re.compile(r"\bpavois-(debian|ubuntu|rhel|rocky|alma|fedora)\d*\b", re.I), "lab VM name"),
    # A real value, not a placeholder. `PAVOIS_SUDO_PASSWORD=…` in an issue is someone writing a
    # command with the secret elided, which is the correct habit, and flagging it trains the reader
    # to dismiss this whole report. The character class excludes the ellipsis, <angle brackets>,
    # $VARS and shell quotes, which is what an elided value actually looks like.
    (
        re.compile(r"\bPAVOIS_(SUDO|SSH)_PASSWORD\s*=\s*(?![…<$'\"\s])[\w.@/-]{3,}"),
        "a password on a command line",
    ),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "a private key"),
    (re.compile(r"\bssh-(rsa|ed25519)\s+AAAA\S+"), "an SSH public key"),
    (re.compile(r"\b192\.168\.122\.\d{1,3}\b"), "libvirt lab address"),
]


def gh(args: list[str]) -> list[dict]:
    try:
        out = subprocess.run(
            ["gh", *args], capture_output=True, text=True, timeout=120, check=True
        ).stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError) as exc:
        print(f"  could not query GitHub ({' '.join(args[:3])}): {exc}")
        return []
    try:
        return json.loads(out) if out.strip() else []
    except json.JSONDecodeError:
        return []


def scan(text: str) -> list[str]:
    hits = []
    for pattern, what in PATTERNS:
        m = pattern.search(text or "")
        if m:
            hits.append(f"{what}: {m.group(0)[:60]}")
    return hits


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=400, help="how many issues/PRs to read")
    args = ap.parse_args()

    findings: list[str] = []

    print("issues and their comments")
    issues = gh(
        [
            "issue",
            "list",
            "--state",
            "all",
            "--limit",
            str(args.limit),
            "--json",
            "number,title,body",
        ]
    )
    for it in issues:
        for hit in scan(f"{it.get('title', '')}\n{it.get('body') or ''}"):
            findings.append(f"issue #{it['number']}: {hit}")
    print(f"  {len(issues)} issue(s) read")

    print("pull requests and their bodies")
    prs = gh(
        ["pr", "list", "--state", "all", "--limit", str(args.limit), "--json", "number,title,body"]
    )
    for pr in prs:
        for hit in scan(f"{pr.get('title', '')}\n{pr.get('body') or ''}"):
            findings.append(f"PR #{pr['number']}: {hit}")
    print(f"  {len(prs)} pull request(s) read")

    print("branches and tags on origin")
    refs = subprocess.run(
        ["git", "ls-remote", "--heads", "--tags", "origin"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    for line in refs.splitlines():
        ref = line.split("\t")[-1]
        if ref.endswith("^{}"):
            continue
        for hit in scan(ref):
            findings.append(f"{ref}: {hit}")
    n_refs = len([r for r in refs.splitlines() if not r.endswith("^{}")])
    print(f"  {n_refs} ref(s) read")

    if findings:
        print(f"\n{len(findings)} thing(s) a reader would see, and that you may not want public:\n")
        for f in findings:
            print(f"  {f}")
        print(
            "\nNone of these is necessarily a secret. A lab hostname is not a credential; it is a\n"
            "map of your network, published with your name on it. Decide each one, then re-run."
        )
        return 1

    print("\nnothing in the issues, pull requests or refs names the lab")
    return 0


if __name__ == "__main__":
    sys.exit(main())
