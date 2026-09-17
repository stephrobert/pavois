#!/usr/bin/env bash
# Put each defect back, one at a time, and demand same_outside_checkout.sh goes red.
#
# That harness exists because seven bugs of one family were found one at a time, by users, after
# releases. A harness written to catch a family it can no longer demonstrate catching is worth
# nothing: the whole point is that the EIGHTH instance has a shape nobody enumerated, and the only
# evidence it would be caught is that the seven known ones still are.
#
# Each case reverts one fix in a COPY of the module, rebuilds, and demands a failure.
#
# Usage: tools/release/falsify_outside_checkout.sh     (minutes: a rebuild per case)
set -uo pipefail
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$SRC" || exit 1

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

bash "$SRC/tools/release/embed_reference.sh" >/dev/null || exit 1
[ -d "$SRC/go/internal/corpus/profiles/linux" ] || { echo "run: mise run embed:corpus" >&2; exit 2; }

case_run() { # <label> <file under go/> <find> <replace> <what the harness must mention>
  local label=$1 file=$2 find=$3 replace=$4 expect=$5
  rm -rf "$work/go"
  cp -r "$SRC/go" "$work/go"
  rm -f "$work/go/pavois"
  python3 - "$work/go/$file" "$find" "$replace" <<'PY' || { echo "  [VOID] $label: the mutation did not apply"; fails=$((fails+1)); return; }
import sys, pathlib
p, find, repl = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
s = p.read_text(encoding="utf-8")
if s.count(find) != 1:
    sys.exit(f"expected exactly one occurrence, found {s.count(find)}")
p.write_text(s.replace(find, repl, 1), encoding="utf-8")
PY
  ( cd "$work/go" && go build -o "$work/pavois-mutant" . ) >/dev/null 2>&1 \
    || { echo "  [VOID] $label: the mutant did not compile, so it proves nothing"; fails=$((fails+1)); return; }
  local rc=0
  out=$(bash --noprofile --norc "$SRC/tools/release/same_outside_checkout.sh" "$work/pavois-mutant" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  [FAIL] $label: the defect is back and the harness stayed GREEN"
    fails=$((fails + 1))
  elif printf '%s' "$out" | grep -qiF "$expect"; then
    echo "  [ ok ] $label: caught, and named"
  else
    echo "  [FAIL] $label: caught, but the message does not mention '$expect'"
    printf '%s\n' "$out" | grep -E '^\s+-' | sed 's/^/         /'
    fails=$((fails + 1))
  fi
}

echo "putting each defect back, the harness must go red for each:"

# #295: the report's platform is resolved by asking the filesystem only.
case_run "harden plan --from ignores the report (#295)" \
  "cmd/harden.go" \
  'if corpus.Has(filepath.Join("linux", cand)) {' \
  'if false && corpus.Has(filepath.Join("linux", cand)) {' \
  "harden plan --from"

# #296: the ruleset digest falls back to nothing, silently. Neutered by making the embedded
# extraction yield no digest, which is what the filesystem-only version did.
case_run "bundle writes an empty ruleset digest (#296)" \
  "cmd/provenance.go" \
  '		return dirDigest(dest)' \
  '		_ = dest' \
  "ruleset"

echo
if [ "$fails" -gt 0 ]; then
  echo "$fails case(s) wrong: the harness does not catch what it claims to."
  exit 1
fi
echo "the harness catches every defect it was written for."
