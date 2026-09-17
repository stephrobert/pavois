#!/usr/bin/env bash
# THE INVARIANT: for everything Pavois ships inside itself, a downloaded binary must behave from an
# empty directory exactly as it behaves from a checkout.
#
# Every defect of this family found so far was found one command at a time, by a user, after a
# release:
#
#   v0.1.0  scan               "no bundled profile for debian 12.15"
#   v0.1.2  harden plan        "this binary embeds none and none is on disk"   (#286)
#   v0.1.2  rules/norms/oscal  the same, on three commands the issue did not name
#   v0.1.3  verify             answered with an internal repository path
#   v0.1.3  oscal              would have published a catalogue dated 1970-01-01
#   open    harden plan --from ignores the report's platform and probes the target   (#295)
#   open    bundle             writes ruleset_sha256: "" and says nothing            (#296)
#
# Seven instances, one cause, discovered seven times. Grep does not generalise: each was a
# DIFFERENT lookup, and the eighth will be a shape nobody enumerated. So this does not look for
# shapes. It runs the SAME binary twice, from the repository and from an empty directory, and
# compares. A difference in what the binary KNOWS is a defect by construction, whatever produced it.
#
# What it deliberately does not cover: anything that needs a live target (scan against a host,
# harden apply, verify's network probes) and anything whose output legitimately depends on the
# working directory (reports/, serve). Those are the scenario's job, on a VM.
#
# Usage: tools/release/same_outside_checkout.sh [path-to-binary]     (default: a release build)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
ROOT=$PWD

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { GREEN=""; RED=""; DIM=""; OFF=""; }
fails=0
ok() { printf "  %s+%s %s\n" "$GREEN" "$OFF" "$1"; }
ko() { printf "  %s-%s %s\n    %s%s%s\n" "$RED" "$OFF" "$1" "$DIM" "$2" "$OFF"; fails=$((fails + 1)); }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

BIN=${1:-}
if [ -z "$BIN" ]; then
  mise run embed:all >/dev/null 2>&1 || { echo "embed failed (mise run embed:all)" >&2; exit 2; }
  ( cd go && CGO_ENABLED=0 go build -trimpath -o "$work/pavois" . ) \
    || { echo "go build failed" >&2; exit 2; }
  BIN="$work/pavois"
fi
[ -x "$BIN" ] || { echo "no binary at $BIN" >&2; exit 2; }
BIN=$(readlink -f "$BIN")

# An empty directory with no profiles/ and no docs/ anywhere above it. /tmp, never a subdirectory
# of the repository: a parent carrying profiles/ hides the very failure this exists to catch.
outside="$work/empty"
mkdir -p "$outside"

# Differences that are NOT defects: a uuid derived from content and time, a timestamp, an absolute
# path that legitimately names where the command ran. Everything else has to match byte for byte.
normalise() {
  sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' \
    | sed -E 's#[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}#<uuid>#g' \
    | sed -E 's#[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z?#<timestamp>#g' \
    | sed -E "s#${work}[^ \"']*#<tmp>#g; s#${ROOT}[^ \"']*#<root>#g" \
    | sed -E 's#/tmp/[A-Za-z0-9._-]+#<tmp>#g'
}

# <label> <args...> : run from the repository and from the empty directory, demand the same answer.
same() {
  local label=$1; shift
  local a b
  a=$( cd "$ROOT"    && "$BIN" "$@" 2>&1 | normalise )
  b=$( cd "$outside" && "$BIN" "$@" 2>&1 | normalise )
  if [ "$a" = "$b" ]; then
    ok "$label ($(printf '%s' "$a" | wc -c) bytes, identical)"
    return
  fi
  # Which side is poorer is the useful half of the message: a shorter answer outside is content the
  # binary has and cannot reach.
  local na nb first
  na=$(printf '%s' "$a" | wc -c); nb=$(printf '%s' "$b" | wc -c)
  first=$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -m1 '^[<>]' | cut -c1-120)
  ko "$label differs: $na bytes in the checkout, $nb outside" "$first"
}

echo "the same binary, from the repository and from an empty directory"
echo "  $BIN"
echo

echo "== what the binary knows about itself"
same "pavois version"                version
same "pavois profiles"               profiles
same "pavois standards"              standards

echo
echo "== the embedded reference, every way it is read"
for os in debian12 debian13 ubuntu2404 rhel9 fedora; do
  same "pavois rules --os $os"       rules --os "$os"
done
same "pavois norms"                  norms
same "pavois oscal"                  oscal

echo
echo "== the commands that consume a report, which needs no target"
cp docs/examples/before.json docs/examples/after.json "$work/"
same "pavois diff before after"      diff "$work/before.json" "$work/after.json"
# #295: --from exists so a plan needs nothing but the file. Outside a checkout it ignores the
# report's platform and falls back to probing the target, which defeats the flag.
same "pavois harden plan --from"     harden plan somehost --from "$work/after.json" --out "$work/plan-cmp"

echo
echo "== doctor, which is what a user runs when something is wrong"
# doctor reads the environment too (engine, sudo, ssh), and those lines are the same on both runs
# because it is the same machine. What must not differ is the inventory of what the binary carries.
#
# Compared verbatim, with ONE substitution: the provenance of the rule corpus, which legitimately
# says where it was read from and is the useful half of that line. Everything else, including every
# count, must match exactly.
#
# The first attempt reduced each line to "label = <number>" with a sed regex. sed has no lazy
# quantifier, so `.*?([0-9]+)` captured the LAST digit on the line: a nine-system reference reduced
# to "= 4", from ubuntu2604. Both sides reduced to the same noise and the check went green having
# measured nothing, which is the failure this whole file exists to catch, one level up.
assets() {
  normalise \
    | grep -E 'reference|catalogue|baseline|ruleset|probes|recipes|corpus' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g' \
    | sed -E 's/\((rendered on disk|embedded in this binary)\)/(<provenance>)/'
}
a=$( cd "$ROOT"    && "$BIN" doctor 2>&1 | assets )
b=$( cd "$outside" && "$BIN" doctor 2>&1 | assets )
if [ "$a" = "$b" ]; then
  ok "pavois doctor reports the same embedded assets from both"
else
  ko "pavois doctor describes a different binary depending on where it runs" \
     "$(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | grep -m1 '^[<>]' | cut -c1-120)"
fi

echo
echo "== bundle, whose whole purpose is an artifact somebody reads later"
# #296: the manifest carries the ruleset's CONTENT digest because a version string is not enough to
# say which rules produced a verdict. Outside a checkout it is written as "" with no error.
for where in "$ROOT" "$outside"; do
  d="$work/bundle-$(basename "$where")"
  ( cd "$where" && "$BIN" bundle "$work/before.json" "$work/after.json" --out "$d" ) >/dev/null 2>&1
done
digest_of() { find "$1" -name '*.json' -exec grep -ho '"ruleset_sha256": *"[^"]*"' {} + 2>/dev/null | head -1; }
din=$(digest_of "$work/bundle-$(basename "$ROOT")")
dout=$(digest_of "$work/bundle-empty")
if [ -z "$din" ] && [ -z "$dout" ]; then
  ko "bundle produced no manifest at all" "neither run wrote a ruleset_sha256 field"
elif [ "$din" = "$dout" ]; then
  ok "bundle records the same ruleset digest from both"
else
  ko "bundle records a different ruleset identity depending on where it runs" \
     "checkout: ${din:-<none>} / outside: ${dout:-<none>}"
fi

echo
if [ "$fails" -gt 0 ]; then
  printf "%s%d command(s) answer differently outside a checkout.%s\n" "$RED" "$fails" "$OFF" >&2
  echo "Each one is content the binary carries and cannot reach. The fix is never a new lookup:" >&2
  echo "read the embedded copy when the disk has none, and never return an empty value for it." >&2
  exit 1
fi
echo "${GREEN}the binary knows the same things wherever it runs.${OFF}"
