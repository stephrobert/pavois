#!/usr/bin/env bash
# Merge every open pull request together and run the full local gate on the RESULT.
#
# Each pull request is green against main, individually. Nothing has ever built the combination,
# and the combination is what lands. Two ways that bites, and both are already in the tree:
#
#   - a textual conflict: two branches append a step to the same workflow at the same place
#   - a semantic one, which is worse because git merges it silently: one branch regenerates a
#     file another branch's generator also writes, and the merge is clean while the result is not
#
# It runs in a throwaway git worktree, so the working tree, the index and the current branch are
# untouched, and the worktree is removed on exit whatever happens.
#
# Usage:
#   tools/validate_prs.sh                       every open pull request, oldest first
#   tools/validate_prs.sh 331 332 336           only those, in that order
#   tools/validate_prs.sh --all-branches        every open pull request PLUS every pushed branch
#                                               that has no pull request yet
#   tools/validate_prs.sh 331 feat/my-branch    numbers are pull requests, anything else a branch
#   FAST=1 tools/validate_prs.sh                skip the site build (the slow half)

set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT" || exit 1

WORK=$(mktemp -d -t pavois-pr-validate-XXXXXX)
BRANCH="zz-pr-integration-$$"
cleanup() {
  cd "$REPO_ROOT" || return
  git worktree remove --force "$WORK/tree" >/dev/null 2>&1
  git branch -D "$BRANCH" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  \033[32mOK  \033[0m %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }

# ---------------------------------------------------------------- which pull requests

ALL_BRANCHES=0
ARGS=()
for a in "$@"; do
  if [ "$a" = "--all-branches" ]; then ALL_BRANCHES=1; else ARGS+=("$a"); fi
done

if [ "${#ARGS[@]}" -gt 0 ]; then
  PRS=("${ARGS[@]}")
else
  mapfile -t PRS < <(gh pr list --state open --base main --json number --jq '.[].number' | sort -n)
fi

# Work in progress is still work that lands. A branch pushed without a pull request merges on the
# same day as the rest, and leaving it out is how the one thing nobody reviewed breaks the batch.
if [ "$ALL_BRANCHES" = 1 ]; then
  mapfile -t withpr < <(gh pr list --state open --base main --json headRefName --jq '.[].headRefName')
  while read -r b; do
    [ "$b" = "main" ] && continue
    for h in "${withpr[@]}"; do [ "$b" = "$h" ] && continue 2; done
    PRS+=("$b")
  done < <(git ls-remote --heads origin | sed 's#.*refs/heads/##')
fi

if [ "${#PRS[@]}" -eq 0 ]; then
  echo "no open pull request to validate"
  exit 0
fi

say "Validating ${#PRS[@]} change(s) merged together: ${PRS[*]}"

# Everything is merged onto the CURRENT origin/main, not onto a local main that may lag behind.
git fetch --quiet origin main || { bad "could not fetch origin/main"; exit 2; }
git worktree add --quiet --detach "$WORK/tree" origin/main || { bad "could not create the worktree"; exit 2; }
cd "$WORK/tree" || exit 2
git switch --quiet -c "$BRANCH" || exit 2

# ---------------------------------------------------------------- merge them, one at a time

say "Merging"
conflicted=()
merged=()
for pr in "${PRS[@]}"; do
  if [[ "$pr" =~ ^[0-9]+$ ]]; then
    head=$(cd "$REPO_ROOT" && gh pr view "$pr" --json headRefName --jq .headRefName 2>/dev/null)
    if [ -z "$head" ]; then
      bad "#$pr: no such pull request"
      conflicted+=("$pr")
      continue
    fi
  else
    head="$pr"   # a branch with no pull request yet
  fi
  git fetch --quiet origin "$head" || { bad "#$pr ($head): could not fetch"; conflicted+=("$pr"); continue; }
  if git merge --quiet --no-edit -m "merge #$pr ($head)" FETCH_HEAD >/dev/null 2>&1; then
    ok "#$pr  $head"
    merged+=("$pr")
  else
    # Name the files, because "it conflicts" is not actionable and the resolution is usually
    # obvious once you see that both sides only ADDED something.
    files=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
    bad "#$pr  $head  CONFLICTS in: ${files:-unknown}"
    git merge --abort >/dev/null 2>&1
    conflicted+=("$pr")
  fi
done

if [ "${#merged[@]}" -eq 0 ]; then
  bad "nothing merged cleanly, there is no combination to test"
  exit 1
fi

# ---------------------------------------------------------------- the gate, on the result

# The corpus (profiles/linux/**.rb) and the per-OS reference are DERIVED and gitignored, so a
# fresh worktree has neither. Skipping this does not make the gate fail loudly, which is worse:
# lint:shell-first-word finds no command and reports "nothing was verified", a guard measuring its
# own absence. Render first, then gate.
say "Preparing the worktree (the corpus is derived, a fresh checkout has none)"
printf '  %-24s ' "render"
if mise run render > "$WORK/render.log" 2>&1; then
  printf '\033[32mOK\033[0m\n'
else
  printf '\033[31mFAIL\033[0m\n'
  sed -e 's/\x1b\[[0-9;]*m//g' "$WORK/render.log" | tail -20 | sed 's/^/        /'
  bad "the merged result cannot even render its corpus"
  exit 1
fi

STEPS=(prepush)
if [ "${FAST:-0}" != "1" ]; then
  STEPS+=(test lint site:verify site:build site:links site:validate-seo site:validate-hreflang)
fi

say "Running the gate on the merged result (${#merged[@]} change(s): ${merged[*]})"
failed=()
for step in "${STEPS[@]}"; do
  printf '  %-24s ' "$step"
  if mise run "$step" > "$WORK/${step//:/-}.log" 2>&1; then
    printf '\033[32mOK\033[0m\n'
  else
    printf '\033[31mFAIL\033[0m\n'
    failed+=("$step")
    sed -e 's/\x1b\[[0-9;]*m//g' "$WORK/${step//:/-}.log" | tail -25 | sed 's/^/        /'
  fi
done

# A generated tree that the gate rewrote is a finding too: it means a merged branch shipped a
# stale projection, which is what the fiche drift was. Report it rather than leaving it in a
# worktree nobody will look at again.
dirty=$(git status --porcelain | wc -l)

# ---------------------------------------------------------------- verdict

say "Verdict"
echo "  merged cleanly : ${#merged[@]}  (${merged[*]})"
if [ "${#conflicted[@]}" -gt 0 ]; then
  echo "  conflicted     : ${#conflicted[@]}  (${conflicted[*]})"
fi
echo "  gate steps     : $(( ${#STEPS[@]} - ${#failed[@]} ))/${#STEPS[@]} green"
if [ "$dirty" -gt 0 ]; then
  echo "  NOTE: the gate rewrote $dirty generated file(s); a merged branch carries a stale projection"
fi

if [ "${#failed[@]}" -gt 0 ] || [ "${#conflicted[@]}" -gt 0 ]; then
  echo
  [ "${#failed[@]}" -gt 0 ] && echo "  failed steps: ${failed[*]}"
  exit 1
fi
echo
echo "  the ${#merged[@]} pull requests build and pass together."
