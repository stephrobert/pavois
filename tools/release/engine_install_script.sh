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

# The target OS, in omnitruck's own spelling, as the page lists it: el/8, el/9, debian/12,
# debian/13, ubuntu/22.04, ubuntu/24.04. Default ubuntu/24.04, which is what both callers used
# before this was a parameter at all.
#
# It HAD to become one. The substitution was hardcoded to ubuntu/24.04 whatever the target, so
# pointing the scenario at a debian 12 VM installed the Ubuntu package on it: glibc 2.39 against
# Debian's 2.36, an engine that cannot start, and a run that measured nothing while reporting
# green. The script's whole claim is that it runs THE DOCUMENTATION'S OWN COMMANDS; a reader on
# Debian substitutes debian/12, so this has to substitute it too.
TARGET=${1:-ubuntu/24.04}
case "$TARGET" in
  */*) P=${TARGET%%/*}; PV=${TARGET#*/} ;;
  *)   echo "engine_install_script.sh: expected <family>/<version>, got '$TARGET'" >&2; exit 2 ;;
esac
# The package manager follows the family, exactly as the block's own trailing comment says.
case "$P" in
  debian|ubuntu) INSTALL='sudo apt-get install -y' ;;
  el|fedora)     INSTALL='sudo dnf install -y' ;;
  *) echo "engine_install_script.sh: no package manager known for '$P'" >&2; exit 2 ;;
esac

# The minimal cloud images have no curl, and the block's first act is to download with it. Root in a
# VM, a sudo-capable user on a runner: both, without assuming which. The package manager follows
# the family too: this used to be hardcoded to apt-get, which meant an el target failed on the
# script's very first line, before reaching the substitutions below that claim to support it.
#
# Both forms are spelled out rather than derived by prefixing `sudo`, because `sudo a && b` runs
# only `a` as root: the apt form is two commands, and the second one silently lost its privileges.
case "$P" in
  debian|ubuntu)
    AS_ROOT='apt-get update -qq && apt-get install -y -qq curl'
    AS_USER='sudo apt-get update -qq && sudo apt-get install -y -qq curl' ;;
  el|fedora)
    AS_ROOT='dnf install -y -q curl'
    AS_USER='sudo dnf install -y -q curl' ;;
esac
cat <<PRELUDE
set -e
if ! command -v curl >/dev/null 2>&1; then
  if [ "\$(id -u)" -eq 0 ]; then
    $AS_ROOT
  else
    $AS_USER
  fi
fi
PRELUDE

mise exec -- node --experimental-strip-types tools/doc_commands.mjs --id engine-install \
  | sed -e "s|p=el&pv=9|p=${P}\&pv=${PV}|" \
        -e "s|sudo dnf install -y|${INSTALL}|" \
        -e 's|^pavois doctor.*|true|'
