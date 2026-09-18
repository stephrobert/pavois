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
#   tools/validate_prs.sh --vm                  ALSO run the real first-run scenario on a
#                                               disposable debian/12 VM (~20 min). Everything
#                                               else is offline and touches no machine.
#   tools/validate_prs.sh --os ubuntu/24.04     the same, on another image (implies --vm)

set -uo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT" || exit 1

WORK="${TMPDIR:-/tmp}/pavois-pr-validate"

# golangci-lint caches results keyed by ABSOLUTE path, and this harness lints a directory that is
# deleted at the end of every run. The cache then replays entries pointing into a worktree that no
# longer exists and fails on every Go file with "no such file or directory": `lint` and `prepush`
# both went red on code that is fine, which is a harness measuring itself.
#
# A fixed WORK path is not enough, and that was the first fix: entries written by earlier runs,
# under their own random directories, are still in the shared cache and keep being replayed. So the
# cache is ISOLATED in the throwaway tree instead. It costs a cold lint each run, and it means this
# script cannot poison, or be poisoned by, the cache `mise run lint` uses in the real checkout.
export GOLANGCI_LINT_CACHE="$WORK/golangci-cache"
# The logs OUTLIVE the run. They used to live under the directory the trap removes, so the one
# thing needed to diagnose a failure was deleted the moment the failure was reported.
LOGS="$REPO_ROOT/.pr-validate-logs"
BRANCH="zz-pr-integration-$$"
cleanup() {
  cd "$REPO_ROOT" || return
  git worktree remove --force "$WORK/tree" >/dev/null 2>&1
  git branch -D "$BRANCH" >/dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM
rm -rf "$WORK" "$LOGS"
mkdir -p "$WORK" "$LOGS"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  \033[32mOK  \033[0m %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; }

# A long step reports WHILE it runs, or it is indistinguishable from a hung one.
#
# This used to print the step name and then nothing until it finished. site:build alone is about
# ninety seconds, so the whole gate spent minutes looking identical to a crash, and the only way to
# know it was alive was to go and read the log by hand. Reporting on completion is not reporting as
# you go: the interesting moment is the silence, not the verdict.
#
# Every HEARTBEAT seconds it prints the elapsed time and the last line the step wrote, which is
# also what tells a slow step apart from a stuck one.
HEARTBEAT="${HEARTBEAT:-30}"

run_step() {  # label, logfile, cmd... -> exit status of the command
  local step="$1" log="$2" pid elapsed=0 last
  shift 2
  "$@" > "$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ "$((elapsed % HEARTBEAT))" -eq 0 ]; then
      last=$(sed -e 's/\x1b\[[0-9;]*m//g' "$log" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n1)
      printf '\n      %3ds  %-22s %s' "$elapsed" "$step" "${last:0:70}"
    fi
  done
  wait "$pid"
  local rc=$?
  [ "$elapsed" -ge "$HEARTBEAT" ] && printf '\n  %-24s ' "$step"   # re-anchor the OK/FAIL column
  return "$rc"
}


# ---------------------------------------------------------------- which pull requests

ALL_BRANCHES=0
VM_STAGE=0
VM_OS="${VM_OS:-debian/12}"
ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all-branches) ALL_BRANCHES=1; shift ;;
    --vm)           VM_STAGE=1; shift ;;
    --os)           VM_OS="$2"; VM_STAGE=1; shift 2 ;;
    *)              ARGS+=("$1"); shift ;;
  esac
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
if run_step render "$LOGS/render.log" mise run render; then
  printf '\033[32mOK\033[0m\n'
else
  printf '\033[31mFAIL\033[0m\n'
  sed -e 's/\x1b\[[0-9;]*m//g' "$LOGS/render.log" | tail -20 | sed 's/^/        /'
  bad "the merged result cannot even render its corpus"
  exit 1
fi

STEPS=(prepush)
if [ "${FAST:-0}" != "1" ]; then
  STEPS+=(test lint site:verify site:build site:links site:validate-seo site:validate-hreflang)
fi

say "Running the gate on the merged result (${#merged[@]} change(s): ${merged[*]})"
echo "  (a heartbeat every ${HEARTBEAT}s while a step runs, with the last line it wrote)"
failed=()
for step in "${STEPS[@]}"; do
  printf '  %-24s ' "$step"
  if run_step "$step" "$LOGS/${step//:/-}.log" mise run "$step"; then
    printf '\033[32mOK\033[0m\n'
  else
    printf '\033[31mFAIL\033[0m\n'
    failed+=("$step")
    sed -e 's/\x1b\[[0-9;]*m//g' "$LOGS/${step//:/-}.log" | tail -25 | sed 's/^/        /'
  fi
done

# ---------------------------------------------------------------- the real one, on a VM
#
# Everything above is OFFLINE. It proves the merged tree builds, lints and renders; it touches no
# machine and therefore proves nothing about what pavois DOES. This repository's own rule is that a
# change to what a target audits is verified by a real run on a real VM, and two releases shipped a
# binary that could not do its job precisely because every test ran inside the checkout.
#
# So --vm runs tools/release/scenario.sh against the MERGED tree: it builds that tree's binary as a
# release would, provisions one disposable VM, and walks install, doctor, scan and harden plan from
# a machine that has nothing, with one assertion per closed first-run issue. Twenty minutes or so.
#
# The VM rules it inherits, and they are not negotiable: a VM and never a container, never `local`
# on this workstation, one VM at a time, deleted on exit including on interrupt.
if [ "$VM_STAGE" = 1 ]; then
  if [ "${#failed[@]}" -gt 0 ]; then
    say "Skipping the VM stage"
    bad "the offline gate is red: not spending twenty minutes on a VM to confirm it"
  else
    say "Real validation on a fresh $VM_OS VM (the MERGED binary, on a machine that has nothing)"
    # These VMs run beside the maintainer's own session. Ask before taking 4 GiB of it.
    avail=$(free -g | awk '/^Mem:/{print $7}')
    running=$(incus list --format csv -c n 2>/dev/null | grep -c . || echo 0)
    echo "  host: ${avail:-?} GiB available, $running VM(s) already running"
    if [ "${avail:-0}" -lt 6 ]; then
      bad "under 6 GiB available: refusing to start a VM next to the maintainer's session"
      failed+=("vm:scenario")
    elif [ "$running" -gt 0 ]; then
      bad "$running VM(s) already running: one at a time, so this one is not starting"
      failed+=("vm:scenario")
    else
      printf '  %-24s ' "vm:scenario"
      if run_step vm:scenario "$LOGS/vm-scenario.log" \
           bash --noprofile --norc tools/release/scenario.sh --os "$VM_OS"; then
        printf '\033[32mOK\033[0m\n'
        STEPS+=("vm:scenario")
      else
        printf '\033[31mFAIL\033[0m\n'
        failed+=("vm:scenario")
        STEPS+=("vm:scenario")
        sed -e 's/\x1b\[[0-9;]*m//g' "$LOGS/vm-scenario.log" | tail -30 | sed 's/^/        /'
      fi
    fi
  fi
fi

# A generated tree that the gate rewrote is a finding too: it means a merged branch shipped a
# stale projection, which is what the fiche drift was. Report it rather than leaving it in a
# worktree nobody will look at again.
dirty_files=$(git status --porcelain | sed 's/^...//' | head -12)
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
  printf '        %s\n' $dirty_files
fi
echo "  logs           : $LOGS"

if [ "${#failed[@]}" -gt 0 ] || [ "${#conflicted[@]}" -gt 0 ]; then
  echo
  [ "${#failed[@]}" -gt 0 ] && echo "  failed steps: ${failed[*]}"
  exit 1
fi
echo
echo "  the ${#merged[@]} change(s) build and pass together."
