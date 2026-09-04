#!/usr/bin/env bash
# Record the pavois demo against a real Incus VM.
#
#   PAVOIS_DEMO_HOST=10.0.0.5 PAVOIS_SUDO_PASSWORD=... tools/demo/record.sh
#
# The tape carries __HOST__ rather than an address, and this substitutes it into a temporary copy,
# so a lab address never lands in the repository. The password is passed through the environment,
# never typed on camera: pavois reads PAVOIS_SUDO_PASSWORD when --sudo is used without a prompt.
#
# Requires vhs, ttyd and ffmpeg (all three, vhs drives the other two).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

: "${PAVOIS_DEMO_HOST:?set PAVOIS_DEMO_HOST to the target to scan}"
: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD (it never appears on screen)}"
export PAVOIS_SUDO_PASSWORD

for t in vhs ttyd ffmpeg; do
  command -v "$t" >/dev/null || { echo "$t is required: https://github.com/charmbracelet/vhs" >&2; exit 1; }
done

echo "building the binary the demo will run"
(cd go && go build -o pavois .) || exit 1

# Put `pavois` on PATH so the demo shows the command a user types, not ./go/pavois from a checkout.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
{
  echo '#!/bin/sh'
  echo "exec \"$PWD/go/pavois\" \"\$@\" --key \"\$HOME/.ssh/id_ed25519\""
} > "$tmp/bin/pavois"
chmod +x "$tmp/bin/pavois"
export PATH="$tmp/bin:$PATH"

# The recording runs from a SHORT path: pavois prints the report path on screen, and a deep
# working directory fills two lines of the frame with something nobody needs to read.
short=/tmp/pavois-demo
rm -f "$short"
ln -s "$PWD" "$short"
trap 'rm -rf "$tmp"; rm -f "$short"' EXIT

# `harden plan --from` needs the scan just taken; give it a stable name the tape can type.
mkdir -p reports
latest=$(ls -t reports/*.json 2>/dev/null | head -1)
[ -n "$latest" ] && cp "$latest" reports/last.json

sed "s/__HOST__/$PAVOIS_DEMO_HOST/g" tools/demo/pavois.tape > "$tmp/pavois.tape"
(cd "$short" && vhs "$tmp/pavois.tape") 2>&1 | tail -3

for f in demo-pavois.mp4; do
  [ -f "$f" ] && ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" |
    awk -v f="$f" '{printf "%s: %.0fs\n", f, $1}'
done
