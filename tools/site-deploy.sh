#!/usr/bin/env bash
# Publish pavois.dev from this machine, running the same gates the CI job runs.
#
# .github/workflows/site-deploy.yml is the normal route: every merge to main republishes, which is
# what keeps the site a projection of the corpus rather than whatever someone last remembered to
# upload. This script is the other case, the one that kept being done by hand: a doc fix that has to
# be READ on the real site before it is merged.
#
# It is a script and not a sequence of commands typed from memory because the upload is two passes
# with different cache policies, and getting that wrong is invisible. HTML uploaded with the
# immutable policy stays wrong at the edge for a year; assets uploaded without it are re-fetched on
# every page view. The workflow gets this right, so this file mirrors it rather than reinventing it,
# and the gates come along: uploading a build that fails site:links publishes broken links faster.
#
# Usage:
#   tools/site-deploy.sh              build, gate, upload, invalidate, check
#   tools/site-deploy.sh --skip-gates skip the checks (a re-upload of a build already gated)
#   tools/site-deploy.sh --dry-run    say what would be uploaded, upload nothing
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

BUCKET=s3://pavois-dev-site
DISTRIBUTION=EYT0MDPPDEF19
SITE=https://www.pavois.dev/

SKIP_GATES=0
DRY=""
for a in "$@"; do
  case "$a" in
    --skip-gates) SKIP_GATES=1 ;;
    --dry-run)    DRY="--dryrun" ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

step() { printf '\n=== %s\n' "$1"; }
die()  { printf '\n%s\n' "$1" >&2; exit 1; }

# The credentials, before anything is built: a 12-minute build that ends on "no credentials" is a
# 12-minute build nobody gets back.
step "who is deploying"
aws sts get-caller-identity --query 'Arn' --output text || die "no AWS credentials on this machine"

step "build"
mise run build >/dev/null || die "go build failed (site:build calls the binary to generate the CLI reference)"
mise run site:build || die "the site did not build"

if [ "$SKIP_GATES" = 0 ]; then
  # The same gates, in the same order as the workflow. Each one exists because it caught something:
  # a broken link, a language cluster that was not reciprocal, a 250-character description shown
  # truncated for weeks, a mobile header that wrapped onto two rows because a media query adds no
  # specificity, and install commands that had drifted into three copies saying different things.
  for gate in site:links site:validate-hreflang site:quality site:nav-responsive \
              site:install-single-source site:shell-parity; do
    step "$gate"
    mise run "$gate" || die "$gate failed: fix it before publishing, not after"
  done
fi

# Two passes, because one cache policy cannot serve both. Fingerprinted assets are immutable and
# cached for a year; HTML must not be, or the deploy stays invisible until the TTL runs out.
# --delete removes what the build no longer produces.
step "upload immutable assets"
aws s3 sync site/dist "$BUCKET" $DRY \
  --delete \
  --exclude '*.html' --exclude '*.xml' --exclude '*.txt' --exclude '*.json' \
  --cache-control 'public, max-age=31536000, immutable' \
  || die "the asset upload failed"

step "upload pages"
aws s3 sync site/dist "$BUCKET" $DRY \
  --delete \
  --exclude '*' \
  --include '*.html' --include '*.xml' --include '*.txt' --include '*.json' \
  --cache-control 'public, max-age=0, must-revalidate' \
  || die "the page upload failed"

if [ -n "$DRY" ]; then
  printf '\ndry run: nothing was uploaded, and no cache was invalidated.\n'
  exit 0
fi

step "invalidate the edge cache"
id=$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION" \
       --paths '/*' --query 'Invalidation.Id' --output text) || die "could not create the invalidation"
echo "invalidation $id"
aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION" --id "$id" \
  || die "the invalidation did not complete: the edge may still serve the previous build"

# THE SAME CHECK THE WORKFLOW RUNS, not a second copy of it. This step used to be its own three
# lines demanding 200 on $SITE, and it broke the day the front door became a 301 at the edge: it
# asserted the old bug. The workflow's copy was fixed that morning; this one was not, because
# nobody runs it every day. One check, two callers.
step "does the site answer"
python3 tools/site_answers.py || die "the deployed site does not answer the way it must"

printf '\npublished: %s\n' "$SITE"
