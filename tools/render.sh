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
# uv pins the interpreter and pulls pyyaml on the fly; without it (a from-source clone that
# refuses a toolchain manager, which the docs support), plain python3 + pyyaml is enough.
if command -v uv >/dev/null 2>&1; then
  py=(uv run --with pyyaml python3)
else
  py=(python3)
  python3 -c 'import yaml' 2>/dev/null || {
    echo "render: python3 is missing the pyyaml module (apt install python3-yaml, or use mise/uv)" >&2
    exit 1
  }
fi
for os in "${oses[@]}"; do
  "${py[@]}" tools/render_reference.py "$os"
done

# Real syntax gate: `cinc-auditor check` does NOT catch a broken Ruby string in a control
# (it happily reported "0 errors" on a corpus that failed to parse at exec time). ruby -c does.
# ruby ships with the CINC engine; on a machine that has not installed it yet, the corpus is
# still rendered, we just cannot prove it parses, and we say so rather than failing the render.
if ! command -v ruby >/dev/null 2>&1; then
  echo "render: ruby not found, skipping the syntax gate (it runs once cinc-auditor is installed)" >&2
  exit 0
fi
fail=0
for f in profiles/linux/*/controls/*.rb; do
  ruby -c "$f" >/dev/null 2>&1 || { echo "SYNTAX ERROR in $f"; ruby -c "$f" 2>&1 | head -3; fail=1; }
done
[ "$fail" -eq 0 ] || { echo "render: the corpus does not parse — refusing to ship it"; exit 1; }
