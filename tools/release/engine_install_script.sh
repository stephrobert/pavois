#!/usr/bin/env bash
# Print the script that installs the scan engine, from THE DOCUMENTATION'S OWN BLOCK.
#
# The block comes from site/src/data/install.ts, which is what both install pages render, so a
# harness that retypes it proves the retyped version and keeps certifying the old recipe the day the
# page changes (tools/lint_install_docs.py fails the build if a page grows its own copy).
#
# Exactly two substitutions, and they are the two the documentation tells the reader to make: the
# omnitruck platform keys (the page lists el/8, el/9, debian/12, ubuntu/24.04...) and the package
# manager (the block's own trailing comment says "Debian/Ubuntu: sudo apt install ./<file>").
# Nothing else is touched, so any other drift in the page breaks whoever runs this, which is the
# point. The third substitution is not one: `pavois doctor` is the block's last line and belongs to
# the reader, not to a machine that may not have pavois on its PATH yet.
#
# It prints rather than installs, because the two callers run it on very different machines: the
# scenario pushes it into a disposable VM, and the e2e workflow runs it on the runner, which is the
# control host. The scenario must NEVER run it on ITS control host: that is the maintainer's
# workstation, and nothing in this repository installs software there (#206).
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

# The minimal cloud images have no curl, and the block's first act is to download with it. Root in a
# VM, a sudo-capable user on a runner: both, without assuming which.
cat <<'PRELUDE'
set -e
if ! command -v curl >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    apt-get update -qq && apt-get install -y -qq curl
  else
    sudo apt-get update -qq && sudo apt-get install -y -qq curl
  fi
fi
PRELUDE

mise exec -- node --experimental-strip-types tools/doc_commands.mjs --id engine-install \
  | sed -e 's|p=el&pv=9|p=ubuntu\&pv=24.04|' \
        -e 's|sudo dnf install -y|sudo apt-get install -y|' \
        -e 's|^pavois doctor.*|true|'
