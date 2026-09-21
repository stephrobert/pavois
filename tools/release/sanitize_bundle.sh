#!/usr/bin/env bash
# Prepare a campaign's SEALED BUNDLE for publication, and refuse if anything identifying survives.
#
# WHAT IS PUBLISHED, AND WHY NOT THE REST
#
# Only `bundle/`. Measured on a real campaign, seven files elsewhere in the directory carry the
# target's address in their CONTENT: `campaign.log` (399 occurrences), the three HTML reports,
# `plan1.yml`, `plan2.yml`, `refusal.txt`. Scrubbing all of that is a losing game, and none of it is
# the evidence: the bundle is. It holds `manifest.json` (before/after grades, posture, transitions),
# `campaign-delta.json` (the control ids behind every transition), the two scan reports, and
# `checksums.txt` sealing them.
#
# WHAT STILL HAS TO BE FIXED IN IT
#
# The scan files carry no address in their content, being the raw InSpec reports. Their NAME does:
#
#     20260921-1810_debian12-15_203-0-113-10_D.json
#                                 ^^^^^^^^^^^^
#
# and `checksums.txt` and `manifest.json` both name them. Renaming the scans without following
# through leaves a bundle that no longer verifies, which reads as tampered rather than sanitised.
# And editing `manifest.json` changes ITS hash, which `checksums.txt` also seals: the first version
# of this script did exactly that and left `manifest.json: FAILED`. So the manifest's own line is
# recomputed, and the whole bundle is verified before this returns.
#
#   tools/release/sanitize_bundle.sh <campaign-dir>...
#   tools/release/sanitize_bundle.sh --selftest
set -uo pipefail

# `..._203-0-113-10_D.json` -> `..._D.json`. Four dotted-quad groups joined by dashes, between the
# platform and the grade letter: narrow enough to leave a version like `debian12-15` alone.
ADDR='_[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}-[0-9]{1,3}_'

sanitize_bundle() {
  local bundle=$1 f clean
  shopt -s nullglob

  for f in "$bundle"/*.json "$bundle"/*.html; do
    clean=$(printf '%s' "$f" | sed -E "s/${ADDR}([A-E])\\./_\\1./")
    [ "$f" = "$clean" ] || mv -- "$f" "$clean"
  done

  [ -f "$bundle/manifest.json" ] && sed -i -E "s/${ADDR}([A-E])\\./_\\1./g" "$bundle/manifest.json"
  [ -f "$bundle/checksums.txt" ] || return 0
  sed -i -E "s/${ADDR}([A-E])\\./_\\1./g" "$bundle/checksums.txt"

  # The manifest was just edited, so the hash checksums.txt holds for it is stale. Recompute that
  # one line, in place, leaving the others untouched.
  if [ -f "$bundle/manifest.json" ] && grep -q ' manifest.json$' "$bundle/checksums.txt"; then
    local fresh
    fresh=$(cd "$bundle" && sha256sum manifest.json)
    grep -v ' manifest.json$' "$bundle/checksums.txt" > "$bundle/.sums.tmp"
    printf '%s\n' "$fresh" >> "$bundle/.sums.tmp"
    mv -- "$bundle/.sums.tmp" "$bundle/checksums.txt"
  fi
}

# What counts as "an address survived" has to be decided by the FIELD, never by the shape of the
# number. Two earlier versions of this guard refused a clean bundle, each on a different false
# positive, and a scan report is full of both:
#
#     "cis": ["10.2.1.7", "6.2.3.13"]     CIS control references, hundreds of them
#     net.ipv4.ip_forward=0.0.0.0         a legitimate sysctl value
#
# `10.2.1.7` is a perfectly valid private address AND a perfectly ordinary CIS reference. No regex
# over digits can tell them apart, so the question is not "does this look like an address" but
# "is this in a place that names a target". A guard that fires on correct data is an outage wearing
# a guard's uniform, and the person it blocks learns to pass --force.
TARGET_FIELD='"(id|subject|target|host|hostname|address)"[[:space:]]*:[[:space:]]*"[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"'

verify_bundle() {
  local bundle=$1
  if grep -rqE "$TARGET_FIELD" "$bundle" 2>/dev/null; then
    echo "a target field still names an address inside $bundle" >&2
    grep -rlE "$TARGET_FIELD" "$bundle" >&2
    return 1
  fi
  if find "$bundle" -name '*_[0-9]*-[0-9]*-[0-9]*-[0-9]*_?.*' -print -quit | grep -q .; then
    echo "an address survived in a file name under $bundle" >&2
    return 1
  fi
  # A bundle that no longer verifies is worse than one never published: it reads as tampered.
  if [ -f "$bundle/checksums.txt" ]; then
    (cd "$bundle" && sha256sum -c checksums.txt >/dev/null 2>&1) || {
      echo "$bundle no longer verifies against its own checksums" >&2
      (cd "$bundle" && sha256sum -c checksums.txt 2>&1 | grep -v ': OK$') >&2
      return 1
    }
  fi
  return 0
}

selftest() {
  local tmp bad=0 b
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  b="$tmp/campaign/bundle"
  mkdir -p "$b"

  printf 'scan before\n' > "$b/20260921-1757_debian12-15_203-0-113-10_E.json"
  printf 'scan after\n'  > "$b/20260921-1810_debian12-15_203-0-113-10_D.json"
  printf 'delta\n'       > "$b/campaign-delta.json"
  printf '{"after":{"file":"20260921-1810_debian12-15_203-0-113-10_D.json"},"p":"debian12-15"}\n' \
    > "$b/manifest.json"
  (cd "$b" && sha256sum ./*.json | sed 's#\./##' > checksums.txt)

  sanitize_bundle "$b"

  [ -f "$b/20260921-1810_debian12-15_D.json" ] || { echo "  FAIL: scan not renamed" >&2; bad=1; }
  grep -q 'debian12-15' "$b/manifest.json" || { echo "  FAIL: platform version eaten" >&2; bad=1; }
  grep -q '_D\.json' "$b/checksums.txt" || { echo "  FAIL: checksums not updated" >&2; bad=1; }
  grep -q '_D\.json' "$b/manifest.json" || { echo "  FAIL: manifest not updated" >&2; bad=1; }

  # The one the first version got wrong: the manifest's OWN hash must have been recomputed.
  (cd "$b" && sha256sum -c checksums.txt >/dev/null 2>&1) \
    || { echo "  FAIL: the bundle no longer verifies" >&2; bad=1; }

  verify_bundle "$b" >/dev/null 2>&1 || { echo "  FAIL: verifier rejects a clean bundle" >&2; bad=1; }

  # The false positives that made the first verifier refuse a clean bundle: CIS control references
  # and a sysctl value, which a scan report holds by the hundred.
  local f="$tmp/refs/bundle"
  mkdir -p "$f"
  printf '{"cis":["10.2.1.7","6.1.4.1"],"sysctl":"net.ipv4.ip_forward=0.0.0.0"}\n' \
    > "$f/20260921-1810_debian12-15_D.json"
  (cd "$f" && sha256sum ./*.json | sed 's#\./##' > checksums.txt)
  verify_bundle "$f" >/dev/null 2>&1 \
    || { echo "  FAIL: a CIS reference read as an address" >&2; bad=1; }

  # And the thing it must still catch: a target field naming a real address.
  local g="$tmp/leak/bundle"
  mkdir -p "$g"
  printf '{"run":{"target":{"id":"203.0.113.10"}}}\n' > "$g/20260921-1810_debian12-15_D.json"
  (cd "$g" && sha256sum ./*.json | sed 's#\./##' > checksums.txt)
  verify_bundle "$g" >/dev/null 2>&1 \
    && { echo "  FAIL: a target address was published" >&2; bad=1; }

  # Witness: a bundle with nothing to strip comes out verifying and untouched.
  local c="$tmp/clean/bundle"
  mkdir -p "$c"
  printf 'x\n' > "$c/20260921-1810_debian12-15_D.json"
  (cd "$c" && sha256sum ./*.json | sed 's#\./##' > checksums.txt)
  sanitize_bundle "$c"
  verify_bundle "$c" >/dev/null 2>&1 || { echo "  FAIL: a clean bundle was damaged" >&2; bad=1; }

  [ "$bad" -eq 0 ] && { echo "sanitize_bundle selftest: 9/9 checks"; return 0; }
  return 1
}

if [ "${1:-}" = "--selftest" ]; then
  selftest
  exit $?
fi

[ "$#" -gt 0 ] || { echo "usage: $0 <campaign-dir>... | --selftest" >&2; exit 2; }
rc=0
for d in "$@"; do
  [ -d "$d/bundle" ] || { echo "no bundle under $d, nothing to publish" >&2; continue; }
  sanitize_bundle "$d/bundle"
  verify_bundle "$d/bundle" || rc=1
done
exit "$rc"
