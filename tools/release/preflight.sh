#!/usr/bin/env bash
# Everything that must be true before a pavois tag exists.
#
# It runs locally, before anything irreversible. The workflow's own guards only speak AFTER the tag
# is pushed, and a pushed tag has to be deleted on both sides; a published release with a wrong
# binary cannot be replayed at all. So every check that can be made offline is made here.
#
# It reports every verdict rather than stopping at the first, because stopping first means running
# it five times in a row.
#
# What is specific to this project, and why it is here rather than in CI:
#
#   the corpus     the released binary EMBEDS the rendered controls, so a stale corpus does not
#                  fail a build, it ships. gen:verify and the wrapping lint are therefore release
#                  gates, not just contributor conveniences.
#   the evidence   a compliance scanner's release note is a claim about real machines. evidence.py
#                  checks that the golden-path campaign behind that claim measured the corpus being
#                  released, which is the one thing a green campaign log does not say.
#   the site       three pages currently state that no release is published, and the installation
#                  page says its own download commands will fail. Those sentences become false the
#                  moment the tag exists.
#
# Usage: tools/release/preflight.sh vX.Y.Z
# Exit:  0 ready to tag, 1 something is not.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

VERSION="${1:-}"
# The systems the release claims to have validated. Override when the claim changes:
#   PAVOIS_VALIDATED_OS="debian12 debian13 ubuntu2404" tools/release/preflight.sh v0.2.0
VALIDATED_OS="${PAVOIS_VALIDATED_OS:-debian12 debian13}"
REPORTS="${PAVOIS_REPORTS:-reports}"

GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; OFF=$'\033[0m'
[ -t 1 ] || { GREEN=""; RED=""; DIM=""; OFF=""; }

failures=0
ok() { printf "  %s+%s %s\n" "$GREEN" "$OFF" "$1"; }
ko() { printf "  %s-%s %s\n    %s%s%s\n" "$RED" "$OFF" "$1" "$DIM" "$2" "$OFF"; failures=$((failures + 1)); }
note() { printf "  %s.%s %s\n" "$DIM" "$OFF" "$1"; }
head_() { printf "\n%s\n" "$1"; }

if [ -z "$VERSION" ]; then
  echo "usage: tools/release/preflight.sh vX.Y.Z" >&2
  exit 1
fi

echo "preflight for $VERSION"

# --- the tag itself ----------------------------------------------------------
head_ "the tag"

# The same shape release.yml's guard job enforces. Checked here too so the answer arrives before
# the push rather than after it: `tags: v*` matches v0.9.0-clean-room, a lab tag this repository
# already carries.
if printf '%s' "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-(rc|beta|alpha)\.[0-9]+)?$'; then
  ok "$VERSION is a release version"
else
  ko "$VERSION is not a release version" "only vX.Y.Z, optionally -rc.N / -beta.N / -alpha.N"
fi

if git rev-parse "$VERSION" >/dev/null 2>&1; then
  ko "$VERSION already exists locally" "git tag -d $VERSION, if it was a mistake"
else
  ok "$VERSION is free locally"
fi

if ! git remote | grep -q .; then
  ko "no git remote" "nothing can be released from a repository with no origin"
elif git ls-remote --tags origin "$VERSION" 2>/dev/null | grep -q .; then
  ko "$VERSION already exists on origin" "a published tag must never be moved"
else
  ok "$VERSION is free on origin"
fi

# --- the repository is in a state worth tagging ------------------------------
head_ "the repository"

if [ -z "$(git status --porcelain)" ]; then
  ok "the working tree is clean"
else
  ko "the working tree is dirty" "the tag would name a commit that is not what you tested"
fi

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "main" ]; then
  ok "on main"
else
  ko "on $branch, not main" "tag the branch releases are cut from, or say why not"
fi

# Five steps of the release workflow are gated on the repository being public: GitHub refuses
# attestations on a user-owned private repo, and a Cosign signature goes to the public Rekor log.
# Gated, they SKIP, so a tag pushed while private publishes a green release with no provenance,
# no SBOM attestation and no signature, and says nothing about it.
if command -v gh >/dev/null 2>&1; then
  private="$(gh api 'repos/{owner}/{repo}' --jq '.private' 2>/dev/null)"
  case "$private" in
    false) ok "the repository is public, so the release can be signed" ;;
    true)  ko "the repository is private" \
              "provenance, SBOM attestation and the Cosign signature would all be skipped; make it public first" ;;
    *)     ko "could not ask GitHub whether the repository is public" "gh api failed: check authentication" ;;
  esac
else
  note "gh is not installed, so the public/private gate was not checked"
fi

# --- what the binary will embed ----------------------------------------------
head_ "the corpus the binary embeds"

# profiles/linux/*/controls/ is derived and gitignored, and the release workflow renders it into
# the binary with //go:embed. A stale or unrendered corpus therefore does not fail a build, it
# ships, which is the one failure mode a Go release cannot catch for itself.
if mise run render >/dev/null 2>&1; then
  ok "the corpus renders from docs/reference/rules.yml"
else
  ko "the corpus does not render" "mise run render"
fi

if mise run gen:verify >/dev/null 2>&1; then
  ok "the per-OS reference files match render(rules.yml)"
else
  ko "the per-OS reference files are stale" "mise run gen, then commit"
fi

if mise run lint:shell-first-word >/dev/null 2>&1; then
  ok "every control command runs as the privilege it needs"
else
  ko "a control command would lose its sudo" "mise run lint:shell-first-word"
fi

# --- the gates the project already owns --------------------------------------
head_ "the project's own gates"

if mise run prepush >/dev/null 2>&1; then
  ok "mise run prepush"
else
  ko "mise run prepush fails" "run it to see which gate"
fi

if mise run oscal:verify >/dev/null 2>&1; then
  ok "the OSCAL export is still valid assessment-results"
else
  ko "the OSCAL export no longer validates" "mise run oscal:verify (the site claims conformance)"
fi

if mise run secrets:history >/dev/null 2>&1; then
  ok "no secret anywhere in the history"
else
  ko "the history scan found something" "mise run secrets:history"
fi

# --- the claim about real machines -------------------------------------------
head_ "the field evidence for: $VALIDATED_OS"

# shellcheck disable=SC2086
if python3 tools/release/evidence.py $VALIDATED_OS --reports "$REPORTS"; then
  :
else
  failures=$((failures + 1))
fi

# --- what a reader of the release will look for ------------------------------
head_ "what the site and the docs say"

# These sentences are true today and false the moment the tag exists. The installation page goes
# further: it tells the reader its own commands WILL FAIL. A release whose install page says that
# is worse than no release.
stale="$(grep -rl 'no release is published\|aucune release' site/src/ 2>/dev/null)"
if [ -z "$stale" ]; then
  ok "no page still claims that nothing is released"
else
  ko "pages still claim that no release exists" \
     "$(printf '%s' "$stale" | tr '\n' ' ')"
fi

# CHANGELOG.md carries TWO version streams, the tool and the baseline, and they are at different
# numbers. A bare grep for the version would find the baseline's 0.1.0 section and report that the
# tool's release is documented when it is not, which is the wrong answer given confidently.
# So the search is scoped to the tool stream, between "# The tool" and "# The baseline".
if [ -f CHANGELOG.md ]; then
  tool_stream="$(awk '/^# The tool/{f=1;next} /^# The baseline/{f=0} f' CHANGELOG.md)"
  if [ -z "$tool_stream" ]; then
    ko "CHANGELOG.md has no '# The tool' section" "the two version streams must stay labelled"
  elif printf '%s\n' "$tool_stream" | grep -q "^## \[\{0,1\}${VERSION#v}"; then
    ok "CHANGELOG.md documents the tool release ${VERSION#v}"
  else
    ko "the tool stream of CHANGELOG.md has no section for ${VERSION#v}" \
       "the baseline's own ${VERSION#v} section does not count"
  fi
else
  note "no CHANGELOG.md; the release notes will be generated from the commits"
fi

# --- CI ----------------------------------------------------------------------
head_ "CI"

# A failed measurement and an absent result are different answers, and only one of them is about
# the repository.
if git remote | grep -q . && command -v gh >/dev/null 2>&1; then
  sha="$(git rev-parse HEAD)"
  # A commit GitHub has never seen and a gh that cannot authenticate both make the query fail, and
  # they are entirely different problems: the first says "push first", the second says "log in".
  # Reporting them as one sent the reader to check credentials that were fine.
  if ! git branch -r --contains "$sha" 2>/dev/null | grep -q .; then
    ko "this commit is not on origin" "CI cannot have run on it yet: push the branch first"
  elif runs="$(gh api "repos/{owner}/{repo}/commits/$sha/check-runs?per_page=100" \
             --jq '.check_runs[] | "\(.name)\t\(.conclusion)"' 2>/dev/null)"; then
    state="$(printf '%s\n' "$runs" | awk -F'\t' 'NF {print $2}' | sort -u | paste -sd, -)"
    case "$state" in
      success)      ok "every check is green on this commit" ;;
      "")           ko "no check run found for this commit" "push it and wait for CI" ;;
      *skipped*|*neutral*)
        if printf '%s' "$state" | grep -qE 'failure|cancelled|timed_out'; then
          ko "CI is $state on this commit" "a release is cut from a green commit"
        else
          ok "every check is green on this commit (some skipped)"
        fi ;;
      *)            ko "CI is $state on this commit" "a release is cut from a green commit" ;;
    esac
  else
    ko "could not ask CI about this commit" "gh api failed: check authentication, not the commit"
  fi
else
  note "CI not checked (no remote, or gh is not installed)"
fi

echo
if [ "$failures" -gt 0 ]; then
  printf "%s%d check(s) failed; nothing was tagged.%s\n" "$RED" "$failures" "$OFF" >&2
  exit 1
fi
cat <<EOF
${GREEN}ready.${OFF} Then, and only then:

  git tag -a $VERSION -m "$VERSION"
  git push origin $VERSION

Pushing the tag is what publishes. It cannot be undone quietly: a tag has to be deleted on both
sides, and a release that reached the world has been downloaded.
EOF
