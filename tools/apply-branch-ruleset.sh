#!/usr/bin/env bash
# Protect the default branch. Run this IMMEDIATELY after the repository goes public.
#
# Why it cannot be done before. Branch protection and rulesets are unavailable on a private
# repository under a free plan: the API answers 403 "Upgrade to GitHub Pro or make this repository
# public to enable this feature." So the order everyone assumes — protect, then publish — is not
# available here. It is the reverse, and the gap between the two is the window this script exists
# to close.
#
# Why it matters on the first minute rather than the first day. `plumber.yml` runs with
# `threshold: '100'` and `.plumber.yaml` enables `branchMustBeProtected`. Measured locally against
# this repository on 2026-09-04, before the flip:
#
#     Status: FAILED — score E, 30.0/100, required >= 100
#     Critical: ISSUE-501 "Branch must be protected"  (the ONLY finding; every other control passes)
#
# Plumber also runs with `score-push: 'true'`, which publishes that score to the README badge. So a
# public flip without this script produces, in public: a red Plumber job, a 30/100 badge, and a
# Scorecard Branch-Protection check at zero — none of which reflects the state of the project.
#
# Usage:
#     tools/apply-branch-ruleset.sh [owner/repo]
#
# Idempotent: updates the ruleset of the same name rather than creating a second one.
set -euo pipefail

NAME="main protection"

command -v gh >/dev/null 2>&1 || {
  echo "gh is required: https://cli.github.com" >&2
  exit 1
}

repo="${1:-}"
[ -z "$repo" ] && repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
[ -z "$repo" ] && {
  echo "no repository: pass owner/repo, or set an origin remote" >&2
  exit 1
}

visibility="$(gh repo view "$repo" --json visibility --jq .visibility 2>/dev/null || echo UNKNOWN)"
if [ "$visibility" != "PUBLIC" ]; then
  cat >&2 <<EOF
$repo is $visibility.

Rulesets need a public repository (or GitHub Pro). Flip the repository to public first — that is
the same act that activates CodeQL, Scorecard, Plumber and dependency-review, all four of which
have never run once — then run this script before the first of them completes.
EOF
  exit 2
fi

echo "repository: $repo"

# The required checks are the ones that guard a merge today, named exactly as they appear in the
# Actions UI. A context that does not exist blocks every PR forever, so this list must be updated
# with the workflows, not guessed: verify with
#   gh api repos/OWNER/REPO/commits/main/check-runs --jq '.check_runs[].name'
payload="$(
  cat <<'JSON'
{
  "name": "main protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" }
  ],
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "require_code_owner_review": false,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["merge", "squash", "rebase"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "Build, test, lint, vuln-scan" },
          { "context": "actionlint + zizmor + poutine" },
          { "context": "ruff + bandit" },
          { "context": "TruffleHog" },
          { "context": "Trivy dependency audit" }
        ]
      }
    }
  ]
}
JSON
)"

existing="$(gh api "repos/${repo}/rulesets" --jq ".[] | select(.name == \"${NAME}\") | .id" 2>/dev/null | head -1 || true)"

if [ -n "$existing" ]; then
  echo "updating ruleset #${existing}"
  printf '%s' "$payload" | gh api --method PUT "repos/${repo}/rulesets/${existing}" --input - >/dev/null
else
  echo "creating the ruleset"
  printf '%s' "$payload" | gh api --method POST "repos/${repo}/rulesets" --input - >/dev/null
fi

echo "rules now active on the default branch:"
gh api "repos/${repo}/rules/branches/main" --jq '.[].type' 2>/dev/null | sort -u | sed 's/^/  /'

cat <<'EOF'

`main` no longer accepts a direct push or a force-push; every change goes through an approved pull
request with the five checks above green.

Two things to do right after:
  1. re-run the Plumber workflow — its ISSUE-501 should be gone and the score should leave band E;
  2. give the Plumber job a token carrying Administration:read, otherwise its governance check
     abstains instead of confirming the protection it just gained.

The local hook (tools/hooks/pre-push) keeps refusing pushes to main regardless: it is what covered
this repository while server-side protection was unavailable, and it costs nothing to keep.
EOF
