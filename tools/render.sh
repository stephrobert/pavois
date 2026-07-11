#!/usr/bin/env bash
# Render the pavois reference(s) -> InSpec corpus the scanner runs.
# The reference (docs/reference/pavois-content/<os>.yml) is the source of truth.
#
# Usage: tools/render.sh [<os> ...]   (default: all OS with a reference file)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"

if [ "$#" -ge 1 ]; then
  oses=("$@")
else
  oses=()
  for f in docs/reference/pavois-content/*.yml; do oses+=("$(basename "$f" .yml)"); done
fi
for os in "${oses[@]}"; do
  uv run --with pyyaml python3 tools/render_reference.py "$os"
done

# Real syntax gate: `cinc-auditor check` does NOT catch a broken Ruby string in a control
# (it happily reported "0 errors" on a corpus that failed to parse at exec time). ruby -c does.
fail=0
for f in profiles/linux/*/controls/*.rb; do
  ruby -c "$f" >/dev/null 2>&1 || { echo "SYNTAX ERROR in $f"; ruby -c "$f" 2>&1 | head -3; fail=1; }
done
[ "$fail" -eq 0 ] || { echo "render: the corpus does not parse — refusing to ship it"; exit 1; }
