#!/usr/bin/env bash
# Exercise the asset-list and verification logic of release.yml outside CI.
#
# The upload itself needs the GitHub API and cannot be run here, so what IS testable is the part
# that decides WHAT ships and the part that compares what landed: those are plain shell, and both
# are new. The v0.1.4 incident came from a glob deciding the set, so the replacement's set logic is
# worth failing on purpose before it decides a real release.
set -uo pipefail
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0
ok() { printf '  [ ok ] %s\n' "$1"; }
ko() { printf '  [FAIL] %s\n         %s\n' "$1" "$2"; fails=$((fails + 1)); }

TAG=v9.9.9
v=${TAG#v}
mkdir -p "$work/dist"
cd "$work/dist" || exit 1

# The exact block from release.yml.
make_list() {
  {
    echo pavois-linux-amd64
    echo pavois-linux-arm64
    echo pavois-darwin-amd64
    echo pavois-darwin-arm64
    echo "pavois_${v}_amd64.deb"
    echo "pavois_${v}_arm64.deb"
    echo "pavois-${v}.amd64.rpm"
    echo "pavois-${v}.arm64.rpm"
  } > artifacts.txt
  rc=0
  while read -r f; do
    [ -s "$f" ] || { echo "dist/$f is missing or empty"; rc=1; }
  done < artifacts.txt
  return "$rc"
}

echo "the asset list:"

# 1. Every artifact present: the list is exactly eight, and the stray SBOM copy is not in it.
for f in pavois-linux-amd64 pavois-linux-arm64 pavois-darwin-amd64 pavois-darwin-arm64 \
         "pavois_${v}_amd64.deb" "pavois_${v}_arm64.deb" \
         "pavois-${v}.amd64.rpm" "pavois-${v}.arm64.rpm"; do
  echo "content of $f" > "$f"
done
echo '{"sbom":true}' > pavois-release.cyclonedx.json     # what merge-multiple drops in dist/
if make_list >/dev/null 2>&1 && [ "$(wc -l < artifacts.txt)" -eq 8 ]; then
  ok "eight artifacts, and the stray pavois-release.cyclonedx.json is not one of them"
else
  ko "the list is wrong" "$(wc -l < artifacts.txt) entries"
fi
if grep -q cyclonedx artifacts.txt; then
  ko "the stray SBOM copy is back in the list" "that is exactly what v0.1.4 shipped"
else
  ok "a glob would have taken it; a list does not"
fi

# 2. The checksums cover the list and nothing else.
xargs -a artifacts.txt sha256sum > checksums.txt
if [ "$(wc -l < checksums.txt)" -eq 8 ] && ! grep -q cyclonedx checksums.txt; then
  ok "checksums.txt covers the eight, and lists nothing a consumer cannot download"
else
  ko "checksums.txt is wrong" "$(wc -l < checksums.txt) lines"
fi

# 3. A missing artifact stops the release BEFORE anything is created.
rm -f pavois-darwin-amd64
if make_list >/dev/null 2>&1; then
  ko "a missing artifact did not stop the list step" "it would have shipped seven of eight"
else
  ok "a missing artifact stops it, before any release exists"
fi
echo "content" > pavois-darwin-amd64

# 4. An EMPTY artifact is a missing artifact. A zero-byte binary uploads happily.
: > pavois-linux-arm64
if make_list >/dev/null 2>&1; then
  ko "an empty artifact passed" "-s, not -f: a zero-byte binary uploads and installs as nothing"
else
  ok "an empty artifact is refused too"
fi
echo "content" > pavois-linux-arm64

echo
echo "the verification of what landed:"
make_list >/dev/null 2>&1
# The exact comparison from release.yml, against a faked `gh release view` listing.
verify() {
  while read -r f; do
    want=$(stat -c%s "$f")
    got=$(awk -v n="$f" '$1 == n {print $2}' published.txt)
    if [ -z "$got" ]; then echo "$f is not on the release"; return 1; fi
    if [ "$got" != "$want" ]; then echo "$f is $got bytes on the release, $want on disk"; return 1; fi
  done < artifacts.txt
}

while read -r f; do printf '%s %s\n' "$f" "$(stat -c%s "$f")"; done < artifacts.txt | sort > published.txt
if verify >/dev/null 2>&1; then
  ok "a complete release passes"
else
  ko "a complete release was rejected" "the happy path must pass, or nothing below means anything"
fi

grep -v darwin-amd64 published.txt > tmp && mv tmp published.txt
if verify >/dev/null 2>&1; then
  ko "a missing asset passed verification" "this is the v0.1.4 state, and it must not publish"
else
  ok "a missing asset is caught (the v0.1.4 state)"
fi

while read -r f; do printf '%s %s\n' "$f" "$(stat -c%s "$f")"; done < artifacts.txt | sort > published.txt
awk '$1 == "pavois-linux-amd64" {print $1, 12; next} {print}' published.txt > tmp && mv tmp published.txt
if verify >/dev/null 2>&1; then
  ko "a truncated asset passed verification" "a short upload reports success"
else
  ok "a truncated asset is caught, which no name check would see"
fi

echo
if [ "$fails" -gt 0 ]; then
  echo "$fails case(s) wrong."
  exit 1
fi
echo "the set that ships is decided by a list, and what landed is compared to it."
