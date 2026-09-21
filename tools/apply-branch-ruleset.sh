#!/usr/bin/env bash
# Protect the default branch with a RULESET, and delete the classic protection it replaces.
#
# Run this immediately after the repository goes public: branch protection of either kind is
# unavailable on a private repository under a free plan (403, "Upgrade to GitHub Pro or make this
# repository public"). The order everyone assumes, protect then publish, is not available; it is the
# reverse, and this script closes the gap.
#
# WHY A RULESET AND NOT CLASSIC PROTECTION
#
# Both protect the branch identically. They differ in who can READ them, and that decides a control
# worth 10 points. From ossf/scorecard-action's own documentation:
#
#   "Scorecard Action requires additional permissions if you use GitHub's classic Branch Protection
#    settings and want to see it reflected in your results."
#   "GitHub's new Repository Rules are accessible to Scorecard Action with the workflow's default
#    GITHUB_TOKEN."
#
# Measured here: with classic protection and no PAT, Scorecard reported Branch-Protection as `n/e`.
# Not-evaluated is not a zero, it is worse: the control drops out of the average entirely, so the
# published score describes a repository whose protection nobody measured. Passing a token was
# tried and failed with `401 Bad credentials`, because the only token available was scoped to
# Administration:Read for one Plumber check and nothing else. A ruleset needs no token at all.
#
# WHY ALL FOUR REVIEW SETTINGS, TOGETHER
#
# `scorekit explain Branch-Protection`:
#
#   "un réglage LISIBLE mais faux pèse plus lourd qu'un réglage illisible : tant qu'une donnée est
#    absente elle sort du calcul, une fois exposée et fausse elle casse le tier. Un ruleset à moitié
#    réglé peut donc noter MOINS bien qu'une absence de ruleset."
#
# Scorecard's tiers are sequential. The "Review" tier (4/10 -> 6/10) needs FOUR things AT ONCE: at
# least one approval, a pull request to change code, strict status checks, and last-push approval.
# Setting three of the four exposes the fourth as false and loses the tier. An earlier version of
# this script wrote exactly that ruleset, with require_last_push_approval false.
#
# enforce_admins stays off, deliberately: a solo maintainer cannot approve their own pull request,
# and enforcing this on admins would lock the repository against its only contributor. The bypass is
# an arbitration, not an oversight.
#
# WHY THERE IS NO MERGE QUEUE HERE
#
# The obvious answer to "one pull request at a time, each tested against main" is the merge queue,
# and it is not available to this repository. `merge_queue` is a rule type for repositories owned by
# an ORGANISATION; this one is owned by a user account. Measured, not assumed: the API answers
#
#   422 Validation Failed, "Invalid rule 'merge_queue': "
#
# to the rule with full parameters, with a larger build budget, with the strict up-to-date policy
# off, without required_linear_history, and alone in a brand-new ruleset of its own with no
# parameters at all. Five refusals with an empty reason: it is the rule type, not the tuning.
#
# What stands in for it is `strict_required_status_checks_policy: true` below, which already forbids
# merging a branch that is behind main, plus `mise run merge:one`, which verifies that condition and
# the required checks BEFORE using the admin bypass. The bypass then covers only the review rule
# nobody here can satisfy, instead of covering everything at once. Twelve pull requests merged in one
# batch through that door, and the pipeline went red.
#
# Usage: tools/apply-branch-ruleset.sh [owner/repo]
# Idempotent: updates the ruleset of the same name rather than creating a second one.
set -euo pipefail

NAME="main protection"

command -v gh >/dev/null 2>&1 || { echo "gh is required: https://cli.github.com" >&2; exit 1; }

repo="${1:-}"
[ -z "$repo" ] && repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
[ -z "$repo" ] && { echo "no repository: pass owner/repo, or set an origin remote" >&2; exit 1; }

visibility="$(gh repo view "$repo" --json visibility --jq .visibility 2>/dev/null || echo UNKNOWN)"
if [ "$visibility" != "PUBLIC" ]; then
  echo "$repo is $visibility. Branch protection needs a public repository (or GitHub Pro)." >&2
  exit 2
fi

echo "repository: $repo"

# The checks that must be green before a merge. A context that never runs on a pull request blocks
# every pull request forever, so this list is not guessed: it is the set observed on a real commit,
# minus the ones that cannot gate a merge.
#
#   deploy            runs after the merge, on main. Requiring it would deadlock.
#   Plumber analyze   skipped on Dependabot pull requests (they receive no Actions secrets), so
#                     requiring it would block every one of them.
#
# Verify the names against reality before changing them:
#   gh api repos/OWNER/REPO/commits/main/check-runs --jq '.check_runs[].name'
read -r -d '' payload <<'JSON' || true
{
  "name": "main protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "require_code_owner_review": true,
        "dismiss_stale_reviews_on_push": false,
        "require_last_push_approval": true,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["merge", "squash", "rebase"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "Build, test, lint, vuln-scan" },
          { "context": "Never-auto and corpus integrity" },
          { "context": "actionlint + zizmor + poutine" },
          { "context": "ruff + bandit" },
          { "context": "Trivy dependency audit" },
          { "context": "TruffleHog" },
          { "context": "TruffleHog (full history)" }
        ]
      }
    }
  ]
}
JSON

existing="$(gh api "repos/${repo}/rulesets" --jq ".[] | select(.name == \"${NAME}\") | .id" 2>/dev/null | head -1 || true)"
if [ -n "$existing" ]; then
  echo "updating ruleset #${existing}"
  printf '%s' "$payload" | gh api --method PUT "repos/${repo}/rulesets/${existing}" --input - >/dev/null
else
  echo "creating the ruleset"
  printf '%s' "$payload" | gh api --method POST "repos/${repo}/rulesets" --input - >/dev/null
fi

# Remove the classic protection this replaces. Leaving both would be the worst of the two: GitHub
# applies the union, so the branch stays protected, but Scorecard reads the classic settings it
# cannot see and the whole point of moving is lost.
if gh api "repos/${repo}/branches/main/protection" >/dev/null 2>&1; then
  echo "removing the classic branch protection it replaces"
  gh api --method DELETE "repos/${repo}/branches/main/protection" >/dev/null
fi

echo
echo "rules now active on the default branch:"
gh api "repos/${repo}/rules/branches/main" --jq '.[].type' 2>/dev/null | sort -u | sed 's/^/  /'

cat <<'EOF'

`main` no longer accepts a direct push or a force-push; every change goes through a pull request
with the checks above green.

Re-run Scorecard afterwards: Branch-Protection should leave `n/e` and land a real score, read with
the workflow's own token and no PAT.

The local hook (tools/hooks/pre-push) keeps refusing pushes to main regardless: it is what covered
this repository while server-side protection was unavailable, and it costs nothing to keep.
EOF
