#!/usr/bin/env bash
# Acquire the SECOND independent validation source (SSG / ComplianceAsCode datastreams) for every
# OS pavois ships, so cross-validation always has >=2 sources. Idempotent: downloads the pinned
# SSG release once, extracts each ssg-<os>-ds.xml into the local oracle cache. ansible-lockdown is
# fetched live by cross_validate.py; this script covers the SSG side.
#
#   tools/fetch_datastreams.sh          # ensure all datastreams present
set -euo pipefail

SSG_VERSION="0.1.81"                                   # pinned (no :latest: reproducible oracle)
CACHE="/tmp/oscap-analysis/ssg"
ZIP="/tmp/ssg-${SSG_VERSION}.zip"
OSES=(debian12 debian13 ubuntu2204 ubuntu2404 rhel8 rhel9 fedora)

mkdir -p "$CACHE"

missing=()
for os in "${OSES[@]}"; do
  [ -f "$CACHE/ssg-${os}-ds.xml" ] || missing+=("$os")
done
if [ ${#missing[@]} -eq 0 ]; then
  echo "all datastreams present in $CACHE"
  exit 0
fi
echo "missing datastreams: ${missing[*]}"

if [ ! -f "$ZIP" ]; then
  echo "downloading SSG v${SSG_VERSION}…"
  gh release download --repo ComplianceAsCode/content "v${SSG_VERSION}" \
    --pattern "scap-security-guide-${SSG_VERSION}.zip" --output "$ZIP"
fi

for os in "${missing[@]}"; do
  if unzip -j -o "$ZIP" "scap-security-guide-${SSG_VERSION}/ssg-${os}-ds.xml" -d "$CACHE" >/dev/null 2>&1; then
    echo "  extracted ssg-${os}-ds.xml"
  else
    echo "  (no ssg-${os}-ds.xml in SSG v${SSG_VERSION}: single-source until SSG adds it)"
  fi
done
