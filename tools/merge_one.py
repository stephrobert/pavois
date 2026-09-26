#!/usr/bin/env python3
"""Merge exactly one pull request, or refuse and say which condition failed.

WHY THIS EXISTS

GitHub's merge queue is the right tool for "one at a time, each tested against main". It cannot be
used here: the merge queue is a rule type for repositories owned by an ORGANISATION, and pavois is
owned by a user account. The API refuses the rule even alone in a ruleset of its own, with every
parameter removed, so there is nothing to tune.

What the branch ruleset already says is most of the intent:

  strict_required_status_checks_policy: true

which means a pull request cannot merge while its branch is behind main. Serialisation follows from
that on its own: the moment one merges, every other open pull request is stale and has to be brought
up to date and re-checked before it can merge in turn.

What defeats it is `gh pr merge --admin`, and the awkward part is that --admin is not laziness. The
ruleset also requires one approving review, and GitHub does not let anyone approve their own pull
request, so a solo maintainer can NEVER satisfy that rule. The bypass is structural. Twelve pull
requests merged in one batch went through that door, and the pipeline went red.

So this guard separates the two things the bypass currently lumps together. It verifies, itself and
against the live API, the conditions the bypass would skip:

  - the branch is up to date with main (mergeStateStatus is not BEHIND),
  - every REQUIRED check is present and green on the exact head commit,
  - nothing is still running,
  - main has not moved while we were looking.

and only then merges, with --admin, so the bypass covers the unsatisfiable review rule and nothing
else. The required check list is read from the branch's effective rules on every run rather than
copied here: a guard that keeps its own copy of the gate is a guard that drifts away from it.

USAGE

  mise run merge:one -- 357
  mise run merge:one -- 357 --dry-run     # verify and report, merge nothing
  python3 tools/merge_one.py --selftest   # the decision function, on synthetic cases
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

REPO = "stephrobert/pavois"
BASE_BRANCH = "main"

# mergeStateStatus values that are a refusal on their own, with the sentence to print. BLOCKED is
# deliberately absent: on this repository it is the normal state of a perfectly good pull request,
# because the review requirement can never be satisfied. That is exactly what --admin is for, and
# why this script checks the rest by hand instead of trusting the colour of the merge button.
BAD_MERGE_STATE = {
    "BEHIND": "the branch is behind main. Update it, let the checks re-run, then try again.",
    "DIRTY": "the branch conflicts with main.",
    "UNKNOWN": "GitHub has not finished computing mergeability. Try again in a moment.",
    "DRAFT": "the pull request is a draft.",
}


def gh_json(*args: str):
    out = subprocess.run(["gh", *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError((out.stderr or out.stdout).strip()[:400])
    return json.loads(out.stdout)


def head_of_base() -> str:
    """The commit `main` points at right now."""
    branch = gh_json("api", f"repos/{REPO}/branches/{BASE_BRANCH}", "--jq", "{sha: .commit.sha}")
    return branch["sha"]


def required_contexts() -> set[str]:
    """The checks the branch ruleset actually demands, read live."""
    rules = gh_json("api", f"repos/{REPO}/rules/branches/{BASE_BRANCH}")
    ctx: set[str] = set()
    for r in rules:
        if r.get("type") == "required_status_checks":
            for c in r["parameters"]["required_status_checks"]:
                ctx.add(c["context"])
    return ctx


def normalise_checks(rollup) -> dict[str, str]:
    """statusCheckRollup carries two shapes. Reduce both to {name: STATE}.

    A check that is still running is reported as PENDING rather than dropped, because "not finished"
    and "not required" must not collapse into the same silence.
    """
    seen: dict[str, str] = {}
    for c in rollup or []:
        if c.get("__typename") == "CheckRun" or "conclusion" in c:
            name = c.get("name", "")
            state = c.get("conclusion") or ""
            if (c.get("status") or "").upper() not in ("COMPLETED", ""):
                state = "PENDING"
        else:
            name = c.get("context", "")
            state = c.get("state") or ""
        if not name:
            continue
        state = (state or "PENDING").upper()
        # A context reported more than once (re-run): the worst answer wins, so a re-run that is
        # still going cannot be masked by the successful attempt before it.
        if name in seen and seen[name] != "SUCCESS":
            continue
        seen[name] = state
    return seen


def decide(pr: dict, required: set[str], checks: dict[str, str]) -> list[str]:
    """Every reason NOT to merge. Empty list means go.

    Pure: no network, no side effect. That is what makes it testable.
    """
    refusals: list[str] = []

    if pr.get("state") != "OPEN":
        refusals.append(f"the pull request is {pr.get('state', 'in an unknown state')}, not open.")
        return refusals  # nothing below means anything for a closed pull request

    if pr.get("isDraft"):
        refusals.append("the pull request is a draft.")
    if pr.get("baseRefName") != BASE_BRANCH:
        refusals.append(f"it targets {pr.get('baseRefName')!r}, not {BASE_BRANCH!r}.")

    state = (pr.get("mergeStateStatus") or "UNKNOWN").upper()
    if state in BAD_MERGE_STATE:
        refusals.append(BAD_MERGE_STATE[state])

    if not required:
        # An empty required list would make every check below vacuously satisfied, which reads as
        # "everything passed". It means the ruleset could not be read, and that is a refusal.
        refusals.append("no required check could be read from the branch rules. Refusing blind.")
        return refusals

    for ctx in sorted(required):
        got = checks.get(ctx)
        if got is None:
            refusals.append(f"required check {ctx!r} did not report at all.")
        elif got == "PENDING":
            refusals.append(f"required check {ctx!r} is still running.")
        elif got != "SUCCESS":
            refusals.append(f"required check {ctx!r} is {got}.")

    running = sorted(n for n, s in checks.items() if s == "PENDING" and n not in required)
    if running:
        names = ", ".join(running[:4])
        refusals.append(f"{len(running)} non-required check(s) still running: {names}")

    return refusals


def selftest() -> int:
    """The decision function, on cases the live API cannot be asked to produce on demand.

    The witness matters as much as the refusals: a guard that refuses everything is not a guard,
    it is an outage, and it looks exactly like a strict one from the outside.
    """
    req = {"A", "B"}
    green = {"A": "SUCCESS", "B": "SUCCESS"}
    ok = {"state": "OPEN", "isDraft": False, "baseRefName": "main", "mergeStateStatus": "BLOCKED"}

    cases = [
        ("witness: open, up to date, all required green", ok, req, green, 0),
        ("behind main", {**ok, "mergeStateStatus": "BEHIND"}, req, green, 1),
        ("conflicts", {**ok, "mergeStateStatus": "DIRTY"}, req, green, 1),
        ("already merged", {**ok, "state": "MERGED"}, req, green, 1),
        ("draft", {**ok, "isDraft": True}, req, green, 1),
        ("wrong base", {**ok, "baseRefName": "gh-pages"}, req, green, 1),
        ("a required check failed", ok, req, {**green, "B": "FAILURE"}, 1),
        ("a required check never reported", ok, req, {"A": "SUCCESS"}, 1),
        ("a required check still running", ok, req, {**green, "B": "PENDING"}, 1),
        ("required list empty (ruleset unreadable)", ok, set(), green, 1),
        ("non-required check still running", ok, req, {**green, "C": "PENDING"}, 1),
        # CLEAN is what a repository without the unsatisfiable review rule would report. It must be
        # accepted, or this guard would only ever work on this one repository's quirk.
        ("clean rather than blocked", {**ok, "mergeStateStatus": "CLEAN"}, req, green, 0),
    ]

    bad = 0
    for label, pr, required, checks, want in cases:
        got = decide(pr, required, checks)
        if bool(got) != bool(want):
            expected = "refusal" if want else "go"
            print(f"  FAIL [{label}]: expected {expected}, got {got}", file=sys.stderr)
            bad += 1
    print(f"merge:one selftest: {len(cases) - bad}/{len(cases)} cases")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Merge one pull request, or refuse and say why.")
    ap.add_argument("pr", nargs="?", help="pull request number")
    ap.add_argument("--dry-run", action="store_true", help="verify and report, merge nothing")
    ap.add_argument(
        "--selftest", action="store_true", help="run the decision function on synthetic cases"
    )
    args = ap.parse_args()

    if args.selftest:
        return selftest()
    if not args.pr:
        ap.error("a pull request number is required")

    # Read main FIRST, so the window between "what was verified" and "what lands" is bounded and
    # checkable rather than assumed. Another merge landing inside that window is precisely the
    # situation this guard exists for.
    base_at_check = head_of_base()

    fields = "number,title,state,isDraft,baseRefName,mergeStateStatus,headRefOid,statusCheckRollup"
    pr = gh_json("pr", "view", args.pr, "--repo", REPO, "--json", fields)
    try:
        required = required_contexts()
    except RuntimeError as exc:
        print(f"merge:one: cannot read the branch rules: {exc}", file=sys.stderr)
        return 1

    checks = normalise_checks(pr.get("statusCheckRollup"))
    refusals = decide(pr, required, checks)

    head = pr.get("headRefOid", "")
    print(f"#{pr['number']} {pr['title']}")
    print(
        f"  head {head[:7]}  merge state {pr.get('mergeStateStatus')}  "
        f"{len(required)} required check(s), {len(checks)} reported"
    )

    if refusals:
        print(f"\nmerge:one REFUSES to merge #{pr['number']}:", file=sys.stderr)
        for r in refusals:
            print(f"  - {r}", file=sys.stderr)
        return 1

    if args.dry_run:
        print("\nmerge:one: every condition met. Nothing merged (--dry-run).")
        return 0

    # main must not have moved between the verification above and the merge below, or what was
    # checked is not what lands. --match-head-commit covers the other side: the pull request itself
    # not having been pushed to in the meantime.
    before = head_of_base()
    if before != base_at_check:
        print(f"\nmerge:one REFUSES to merge #{pr['number']}:", file=sys.stderr)
        print(
            f"  - {BASE_BRANCH} moved while this was being verified "
            f"({base_at_check[:7]} -> {before[:7]}). The branch is now behind it. "
            "Nothing merged.",
            file=sys.stderr,
        )
        return 1

    out = subprocess.run(
        [
            "gh",
            "pr",
            "merge",
            str(pr["number"]),
            "--repo",
            REPO,
            "--squash",
            "--admin",
            "--delete-branch",
            "--match-head-commit",
            head,
        ],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        print("\nmerge:one: the merge itself failed", file=sys.stderr)
        print((out.stdout + out.stderr).strip()[-1500:], file=sys.stderr)
        return 1

    after = head_of_base()
    print(f"\nmerge:one: merged. {BASE_BRANCH} {before[:7]} -> {after[:7]}")
    print(
        "  Every other open pull request is now behind main. This guard will refuse them until\n"
        "  each one is brought up to date and re-checked, which is the serialisation the merge\n"
        "  queue would have given us."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
