#!/usr/bin/env bash
# Remove one embedded asset at a time, rebuild, and demand the guard goes red.
#
# A guard that has never rejected anything cannot be told apart from one that cannot. This one was
# written after v0.1.2 shipped with an empty reference, so the question is not academic: the first
# version of check 5 in standalone_binary.sh passed with behavioral-probes.yml and audit.rules
# deleted from the embed. It matched an error string the code no longer produced, and nothing
# exercised the audit ruleset at all. This file is how that was found.
#
# Six assets, six mutants, each one file removed from a COPY of the module. Green on any of them
# means the guard is decorative for that asset.
#
# Usage: tools/release/falsify_embed.sh      (minutes: it rebuilds and re-runs the guard per case)
set -uo pipefail
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$SRC" || exit 1

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

# One copy of the module, with the embed directories filled as a release build leaves them.
bash "$SRC/tools/release/embed_reference.sh" >/dev/null || exit 1
[ -d "$SRC/go/internal/corpus/profiles/linux" ] || { echo "run: mise run embed:corpus" >&2; exit 2; }
cp -r "$SRC/go" "$work/go"
rm -f "$work/go/pavois"

case_run() { # <label> <file under go/internal/reference/> <what must be reported>
  local label=$1 victim=$2 expect=$3
  rm -rf "$work/go/internal/reference/content" "$work/go/internal/reference/catalogue" \
         "$work/go/internal/reference/data"
  cp -r "$SRC/go/internal/reference/content" "$SRC/go/internal/reference/catalogue" \
        "$SRC/go/internal/reference/data" "$work/go/internal/reference/"
  rm -f "$work/go/internal/reference/$victim"
  ( cd "$work/go" && go build -o "$work/pavois-mutant" . ) >/dev/null 2>&1 \
    || { echo "  [VOID] $label: the mutant did not compile, so it proves nothing"; fails=$((fails+1)); return; }
  out=$(bash --noprofile --norc "$SRC/tools/release/standalone_binary.sh" "$work/pavois-mutant" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  [FAIL] $label: removed $victim and the guard stayed GREEN"
    fails=$((fails + 1))
  elif printf '%s' "$out" | grep -qiF "$expect"; then
    echo "  [ ok ] $label: the guard goes red and names it"
  else
    echo "  [FAIL] $label: the guard goes red but does not mention '$expect'"
    printf '%s\n' "$out" | grep -E '^\s+-' | sed 's/^/         /'
    fails=$((fails + 1))
  fi
}

echo "removing one embedded asset at a time, the guard must go red for each:"
case_run "the per-OS reference"  "content/debian12.yml"       "hardening reference"
case_run "the norm catalogue"    "catalogue/norms.yml"        "norm catalogue"
case_run "the baseline identity" "catalogue/baseline.yml"     "baseline identity"
case_run "the audit ruleset"     "data/audit.rules"           "audit ruleset"
case_run "the behavioral probes" "data/behavioral-probes.yml" "behavioral probes"
case_run "a kernel-build recipe" "data/kernel-build/debian12.sh" "kernel-build recipes"

echo
if [ "$fails" -gt 0 ]; then
  echo "$fails case(s) wrong: the guard does not protect what it claims to."
  exit 1
fi
echo "the guard bites on every embedded asset."
