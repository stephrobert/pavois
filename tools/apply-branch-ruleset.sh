#!/usr/bin/env bash
# Protect the default branch. Run this IMMEDIATELY after the repository goes public.
#
# Why it cannot be done before. Branch protection is unavailable on a private repository under a
# free plan: the API answers 403 "Upgrade to GitHub Pro or make this repository public to enable
# this feature." So the order everyone assumes, protect then publish, is not available here. It is
# the reverse, and the gap between the two is the window this script exists to close.
#
# WHAT CHANGED, AND WHY IT MATTERS MORE THAN IT LOOKS
#
# This script used to write a RULESET with required_approving_review_count: 1 and
# require_last_push_approval: false. `scorekit explain Branch-Protection` says why that is worse
# than doing nothing:
#
#   "un réglage LISIBLE mais faux pèse plus lourd qu'un réglage illisible : tant qu'une donnée est
#    absente elle sort du calcul, une fois exposée et fausse elle casse le tier. Un ruleset à moitié
#    réglé peut donc noter MOINS bien qu'une absence de ruleset."
#
# Scorecard's tiers are sequential, and the "Review" tier (4/10 -> 6/10) needs FOUR things TOGETHER:
# at least one approval, a pull request to change code, strict status checks, and last-push
# approval. Setting three of the four exposes the fourth as false and loses the tier.
#
# So the settings here are not designed, they are COPIED from the best-scoring repository in the
# fleet, which is what scorekit exists to find: stephrobert/dsoxlab, 8/10, the highest of seven.
# It uses classic branch protection rather than a ruleset, and the only thing it still lacks is a
# second approver. Read with:
#
#     scorekit explain Branch-Protection
#     gh api repos/stephrobert/dsoxlab/branches/main/protection
#
# enforce_admins stays false, deliberately. A solo maintainer cannot approve their own pull request,
# so enforcing this on admins would lock the repository against its only contributor. That is an
# arbitration, not an oversight, and it is the same one the model repository made.
#
# Usage: tools/apply-branch-ruleset.sh [owner/repo]
# Idempotent: PUT replaces the protection wholesale.
set -euo pipefail

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
# every pull request forever, so this list is not guessed: it is the set of checks observed on a
# real commit, minus the ones that cannot gate a merge.
#
#   deploy            runs after the merge, on main. Requiring it would deadlock.
#   Plumber analyze   fails until this very protection exists, which is circular. Add it once it
#                     passes, so the gate keeps being true rather than becoming aspirational.
#
# Verify the names against reality before changing them:
#   gh api repos/OWNER/REPO/commits/main/check-runs --jq '.check_runs[].name'
read -r -d '' payload <<'JSON' || true
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Build, test, lint, vuln-scan",
      "Never-auto and corpus integrity",
      "actionlint + zizmor + poutine",
      "ruff + bandit",
      "Trivy dependency audit",
      "TruffleHog",
      "TruffleHog (full history)"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "require_last_push_approval": true,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
JSON

printf '%s' "$payload" | gh api --method PUT "repos/${repo}/branches/main/protection" --input - >/dev/null
echo "protection applied"

echo
echo "what is now true of main:"
gh api "repos/${repo}/branches/main/protection" --jq '
  "  pull request required, " + (.required_pull_request_reviews.required_approving_review_count|tostring) + " approval(s)",
  "  last-push approval      " + (.required_pull_request_reviews.require_last_push_approval|tostring),
  "  branch up to date       " + (.required_status_checks.strict|tostring),
  "  required checks         " + (.required_status_checks.contexts|length|tostring),
  "  force-push allowed      " + (.allow_force_pushes.enabled|tostring),
  "  deletion allowed        " + (.allow_deletions.enabled|tostring),
  "  linear history          " + (.required_linear_history.enabled|tostring)'

cat <<'EOF'

Two things to do right after:
  1. re-run the Plumber workflow: ISSUE-501 "Branch must be protected" should be gone;
  2. give the Plumber job a token carrying Administration:read, otherwise its governance check
     abstains instead of confirming the protection it just gained.

The local hook (tools/hooks/pre-push) keeps refusing pushes to main regardless: it is what covered
this repository while server-side protection was unavailable, and it costs nothing to keep.
EOF
