#!/usr/bin/env bash
# Run the binary OUTSIDE the repository, which is the only place the bug lived.
#
# v0.1.0 shipped unusable. Every artifact installed cleanly, `pavois version` printed v0.1.0, the
# rule corpus was genuinely compiled in (`ssh-disable-root-login` appears eleven times in the
# published binary), and then:
#
#     error: no bundled profile for debian 12.15: pass --profile <path|url>
#
# profileForPlatform asked the filesystem whether a profile existed: os.Stat(root/profiles/linux/x).
# Inside a checkout that is true and everything works. Outside one it is always false, so no
# candidate was ever produced and the embedded fallback was never reached. `pavois profiles` printed
# an empty list for the same reason, which reads as "this tool has no rules" rather than as a bug.
#
# Nothing caught it because EVERYTHING ran from the repository: the tests, the golden-path
# campaigns, the preflight. The corpus check in the preflight verifies the repository's corpus, not
# the binary's. The one thing nobody did was cd somewhere else and run the thing.
#
# So this copies the binary to an empty directory, with no profiles/ anywhere above it, and asks it
# to do its job.
#
# Usage: tools/release/standalone_binary.sh [path-to-binary]     (default: go/pavois)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

BIN=${1:-go/pavois}
[ -x "$BIN" ] || { echo "no binary at $BIN (mise run build)" >&2; exit 2; }
SAMPLE=docs/examples/after.json
[ -f "$SAMPLE" ] || { echo "missing $SAMPLE" >&2; exit 2; }

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { GREEN=""; RED=""; DIM=""; OFF=""; }
fails=0
ok() { printf "  %s+%s %s\n" "$GREEN" "$OFF" "$1"; }
ko() { printf "  %s-%s %s\n    %s%s%s\n" "$RED" "$OFF" "$1" "$DIM" "$2" "$OFF"; fails=$((fails + 1)); }

# /tmp, not a subdirectory of the repo: a parent directory carrying profiles/ would hide the very
# failure this exists to catch.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$BIN" "$work/pavois"
cp "$SAMPLE" "$work/sample.json"

echo "running $BIN from $work (no profiles/ anywhere above it)"

# 1. The corpus is compiled in and the listing can see it. An empty list is the symptom a user meets
#    first, and it does not look like an error.
listed=$(cd "$work" && ./pavois profiles 2>&1 | grep -cE '^ +linux/')
if [ "${listed:-0}" -ge 5 ]; then
  ok "pavois profiles lists $listed embedded profile(s)"
else
  ko "pavois profiles lists $listed profile(s) outside the repository" \
     "the corpus is embedded but the listing reads the disk; run: mise run embed:corpus, then rebuild"
fi

# 2. The profile for a real platform resolves, and the scan completes. `--from` replays an archived
#    report, so this needs no target, no transport and no CINC engine: it isolates profile
#    resolution from everything else that could fail.
out=$(cd "$work" && ./pavois scan local --from sample.json --out . 2>&1)
if grep -q 'no bundled profile' <<<"$out"; then
  ko "scan cannot resolve a profile outside the repository" \
     "$(printf '%s' "$out" | grep 'no bundled profile' | head -1)"
elif grep -qE 'grade|Remediable posture' <<<"$out"; then
  ok "scan resolves an embedded profile and grades ($(printf '%s' "$out" | grep -oE 'Remediable posture: grade [A-E]' | head -1))"
else
  ko "scan produced no grade outside the repository" "$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"
fi

# 3. Every OS the reference declares must be embedded. A corpus copied when the tree had eight
#    systems ships a binary that silently cannot scan the ninth, and the only symptom is one
#    platform answering "no bundled profile" while the others work.
expected=$(find profiles/linux -maxdepth 1 -mindepth 1 -type d | wc -l)
if [ "${listed:-0}" -eq "$expected" ]; then
  ok "all $expected profile(s) of profiles/linux are embedded"
else
  ko "the binary embeds $listed profile(s), profiles/linux has $expected" \
     "the embedded copy is stale: mise run embed:corpus, then rebuild"
fi

# 4. The RULE CORPUS is not the only thing compiled in, and this check knew only about it.
#
# v0.1.2 shipped with an embedded corpus and an EMPTY reference: `scan` worked, and `harden plan`,
# `rules`, `norms` and `oscal` all answered "this binary embeds none and none is on disk". The
# release workflow placed the corpus where go:embed picks it up and nothing else, because the
# reference embed did not exist when that step was written. Everything local passed, because a
# local build runs `mise run embed:all`.
#
# So it is the same defect as v0.1.0, one floor down, and this is the check that was missing again:
# the artifact carries FOUR embedded things now, and each of them has a command that proves it.
for probe in "rules --os debian12:hardening reference" \
             "norms:norm catalogue" \
             "oscal:OSCAL catalogue"; do
  cmd=${probe%%:*}
  what=${probe#*:}
  # shellcheck disable=SC2086  # cmd carries its own flags on purpose
  out=$(cd "$work" && ./pavois $cmd 2>&1)
  if printf '%s' "$out" | grep -qE 'embeds none|no such file|no hardening reference|no norm catalogue'; then
    ko "the $what is not embedded (pavois $cmd)" \
       "$(printf '%s' "$out" | grep -iE 'error' | head -1 | cut -c1-110)"
  elif [ "$(printf '%s' "$out" | wc -c)" -lt 400 ]; then
    ko "pavois $cmd returned almost nothing outside a checkout" \
       "an empty catalogue is worse than an error: it succeeds and reports nothing"
  else
    ok "the $what is embedded (pavois $cmd: $(printf '%s' "$out" | wc -c) bytes)"
  fi
done

# 5. The binary carries SIX embedded assets, and the checks above exercise three of them. The other
#    three fail in ways no command surfaces:
#
#      docs/reference/baseline.yml           the OSCAL catalogue declares itself version 0.0.0,
#                                            released 1970-01-01, with no error anywhere. No release
#                                            reached it: oscal failed first, on the reference.
#                                            Embedding the reference is what unlocks it.
#      docs/reference/audit.rules            `harden apply` pushed an EMPTY audit ruleset
#      docs/reference/behavioral-probes.yml  `pavois verify` answered with an internal repo path
#
#    A first version of this check probed `oscal` and `verify` by hand and passed with
#    behavioral-probes.yml and audit.rules deleted from the embed: it was matching an error string
#    the code no longer produces, and nothing exercised the ruleset at all. Proven by deleting each
#    file from a copy of the tree, rebuilding, and demanding red.
#
#    So the check asks the BINARY what it carries. `pavois doctor` enumerates all six and reports
#    FAIL per missing one, which also means a user who meets "this binary embeds none" has one
#    command to run instead of an issue to file. Only the asset lines are read: doctor also grades
#    the engine and sudo, which say nothing about the artifact.
doc=$(cd "$work" && ./pavois doctor 2>&1 | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g')
assets="hardening reference|norm catalogue|baseline identity|audit ruleset|behavioral probes|kernel-build recipes"
missing=$(printf '%s\n' "$doc" | grep -E '^\s*\[FAIL\]' | grep -E "$assets")
carried=$(printf '%s\n' "$doc" | grep -cE '^\s*\[OK  \].*('"$assets"')')
if [ -n "$missing" ]; then
  ko "pavois doctor reports $(printf '%s\n' "$missing" | wc -l) embedded asset(s) missing" \
     "$(printf '%s' "$missing" | head -1 | sed 's/^ *//' | cut -c1-110)"
elif [ "${carried:-0}" -lt 6 ]; then
  ko "pavois doctor accounts for only $carried of the 6 embedded assets" \
     "either an asset was added without a doctor line, or a line was renamed; both hide a gap"
else
  ok "pavois doctor accounts for all 6 embedded assets"
  printf '%s\n' "$doc" | grep -E '^\s*\[OK  \].*('"$assets"')' | sed 's/^ */      /'
fi

echo
if [ "$fails" -gt 0 ]; then
  printf "%s%d check(s) failed: this binary would ship broken.%s\n" "$RED" "$fails" "$OFF" >&2
  exit 1
fi
echo "${GREEN}the binary works on its own.${OFF}"
