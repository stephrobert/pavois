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
