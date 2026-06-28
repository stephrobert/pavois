#!/usr/bin/env bash
# Automated validation harness for pavois — fast tier, no VM, no datastream.
#
#   L1 Reference : the pavois reference (docs/reference/pavois-content/<os>.yml)
#                  is the SOURCE OF TRUTH. Every entry well-formed; rendering the
#                  reference reproduces the committed corpus EXACTLY (fidelity).
#   L2 Load      : ruby -c + cinc-auditor check + go build/vet/test.
#   L3 Grade     : Go A->E test + Go grade == JS grade (same bands).
#
# The VM tier (L4 real execution, L5 remediation round-trip) lives in
# an Incus-fleet harness (kept local, not published).
#
# Usage: tools/validate.sh [--quick]
#   default : L1 L2 L3.
#   --quick : L2 without cinc-auditor check (ruby -c + go only).
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"

QUICK=0
for a in "$@"; do case "$a" in --quick) QUICK=1;; esac; done

fail=0
ok(){ printf '  \033[32m✔\033[0m %s\n' "$1"; }
ko(){ printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }

# ── L1 Reference (source of truth) ─────────────────────────────────────────
echo "L1 — reference integrity & fidelity"
python3 tools/validate_reference.py || fail=$((fail+1))

# ── L2 Load ────────────────────────────────────────────────────────────────
echo "L2 — load"
rerr=0
while IFS= read -r f; do ruby -c "$f" >/dev/null 2>&1 || { rerr=1; echo "    ruby KO: $f"; }; done \
  < <(find profiles -name '*.rb')
[ "$rerr" = 0 ] && ok "ruby -c: all .rb compile" || ko "ruby -c: syntax errors"

if [ "$QUICK" = 0 ] && command -v cinc-auditor >/dev/null; then
  cerr=0
  for p in profiles/linux/*/ profiles/container-baseline profiles/effective-config; do
    [ -f "$p/inspec.yml" ] || continue
    CHEF_LICENSE=accept-silent cinc-auditor check "$p" 2>/dev/null \
      | grep -q 'Valid : *true' || { cerr=1; echo "    cinc check KO: $p"; }
  done
  [ "$cerr" = 0 ] && ok "cinc-auditor check: all profiles Valid" || ko "cinc check: invalid profile"
fi

( cd go && go build ./... ) 2>/dev/null && ok "go build" || ko "go build"
( cd go && go vet ./...  ) 2>/dev/null && ok "go vet"   || ko "go vet"
( cd go && go test ./... ) >/dev/null 2>&1 && ok "go test" || ko "go test"

# ── L3 Grade ───────────────────────────────────────────────────────────────
echo "L3 — grade A->E"
( cd go && go test ./internal/audit/ -run TestGrade ) >/dev/null 2>&1 \
  && ok "Go grade A->E test" || ko "Go grade test"
python3 tools/validate_grade.py && ok "Go grade bands == JS" || ko "Go/JS grade bands diverge"

echo
if [ "$fail" = 0 ]; then printf '\033[32mVALIDATION OK\033[0m\n'; else printf '\033[31m%d gate(s) failed\033[0m\n' "$fail"; fi
exit $((fail > 0 ? 1 : 0))
