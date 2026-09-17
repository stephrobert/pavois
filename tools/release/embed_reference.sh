#!/usr/bin/env bash
# Put into the binary's embed directories everything the binary needs and cannot find on a user's
# machine. One script, called by BOTH `mise run embed:reference` and the release workflow.
#
# It is one script because it was two. The release workflow had its own copy step, written when the
# corpus was the only embedded thing. When the reference embed was added, the mise task learned
# about it and the workflow did not, so v0.1.2 shipped with an embedded corpus and three empty
# directories: `scan` worked, and `harden plan`, `rules`, `norms` and `oscal` all answered
#
#     error: no hardening reference for debian12: this binary embeds none and none is on disk
#
# Every local check passed, because a local build runs this copy first. The artifact a user
# downloads was built by the other path, the one nobody updated. Duplication is what allowed that,
# so the duplication is gone: a directory added here is added for both.
#
# Usage: tools/release/embed_reference.sh [repo-root]     (default: the repository this lives in)
set -euo pipefail
ROOT=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
cd "$ROOT"

# source glob -> embed directory. Everything the binary reads at runtime and cannot ask the user for.
#
#   content/    the per-OS reference        -> harden plan, rules, oscal, norms coverage
#   catalogue/  norms.yml                   -> pavois norms
#   data/       audit.rules, kernel-build/  -> what harden APPLY pushes to the target, and the pair
#               that failed silently: both were read with the error discarded, so an apply ran with
#               an empty ruleset and an empty recipe, and reported success.
COPIES=(
  "docs/reference/pavois-content/*.yml|go/internal/reference/content"
  "docs/reference/norms.yml|go/internal/reference/catalogue"
  "docs/reference/baseline.yml|go/internal/reference/catalogue"
  "docs/reference/audit.rules|go/internal/reference/data"
  "docs/reference/behavioral-probes.yml|go/internal/reference/data"
  "docs/reference/kernel-build/*.sh|go/internal/reference/data/kernel-build"
)

# Clear first, then copy. In two passes because two entries share go/internal/reference/data:
# clearing inside the copy loop deleted the audit ruleset the previous entry had just placed, and
# the result still looked right, since the directory was non-empty either way.
for entry in "${COPIES[@]}"; do
  dst=${entry#*|}
  [ -d "$dst" ] || { echo "missing embed dir $dst (it is tracked via a .keep file)" >&2; exit 1; }
  # Remove only what this script places, never the .keep that keeps the directory in git.
  find "$dst" -maxdepth 1 -type f ! -name '.keep' -delete
done

for entry in "${COPIES[@]}"; do
  src=${entry%%|*}
  dst=${entry#*|}
  compgen -G "$src" >/dev/null || { echo "nothing matches $src" >&2; exit 1; }
  # shellcheck disable=SC2086  # src is a glob on purpose
  cp $src "$dst/"
done

for entry in "${COPIES[@]}"; do
  dst=${entry#*|}
  echo "  $dst: $(find "$dst" -maxdepth 1 -type f ! -name '.keep' | wc -l) file(s)"
done | sort -u

# Verified, not assumed. An embed directory holding only its .keep compiles fine and ships a binary
# that fails at the first command a user runs, which is precisely the defect above.
status=0
for entry in "${COPIES[@]}"; do
  dst=${entry#*|}
  n=$(find "$dst" -maxdepth 1 -type f ! -name '.keep' | wc -l)
  [ "$n" -gt 0 ] || { echo "::error::$dst is empty; the binary would ship without it" >&2; status=1; }
done
exit "$status"
