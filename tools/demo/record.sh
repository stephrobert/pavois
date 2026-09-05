#!/usr/bin/env bash
# Record the pavois demo against a real Incus VM.
#
#   PAVOIS_DEMO_HOST=10.0.0.5 PAVOIS_SUDO_PASSWORD=... tools/demo/record.sh
#
# The tape carries __HOST__ rather than an address, and this substitutes it into a temporary copy,
# so a lab address never lands in the repository. The password is passed through the environment,
# never typed on camera: pavois reads PAVOIS_SUDO_PASSWORD when --sudo is used without a prompt.
#
# PAVOIS_DEMO_HOST appears on screen as typed. Substituting a prettier name for it was tried and
# abandoned: OS detection is `cinc detect`, which resolves the name in Ruby and never goes through
# the ssh binary, so a name with no DNS record fails the scan before it starts. Point this at
# something you are willing to show.
#
# Requires vhs, ttyd and ffmpeg (all three, vhs drives the other two).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

: "${PAVOIS_DEMO_HOST:?set PAVOIS_DEMO_HOST to the target to scan}"
: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD (it never appears on screen)}"
: "${PAVOIS_DEMO_TAPE:=tools/demo/pavois.tape}"
export PAVOIS_SUDO_PASSWORD

for t in vhs ttyd ffmpeg; do
  command -v "$t" >/dev/null || { echo "$t is required: https://github.com/charmbracelet/vhs" >&2; exit 1; }
done

echo "building the binary the demo will run"
(cd go && go build -o pavois .) || exit 1

tmp=$(mktemp -d)
short=/tmp/pavois-demo
trap 'rm -rf "$tmp"; rm -f "$short"' EXIT
mkdir -p "$tmp/bin"

# Put `pavois` on PATH so the demo shows the command a user types, not ./go/pavois from a checkout.
{
  echo '#!/bin/sh'
  echo "exec \"$PWD/go/pavois\" \"\$@\" --key \"\$HOME/.ssh/id_ed25519\""
} > "$tmp/bin/pavois"

chmod +x "$tmp/bin/pavois"
export PATH="$tmp/bin:$PATH"

# The recording runs from a SHORT path: pavois prints the report path on screen, and a deep
# working directory fills two lines of the frame with something nobody needs to read.
rm -f "$short"
ln -s "$PWD" "$short"

# `harden plan --from` needs the scan just taken; give it a stable name the tape can type.
mkdir -p reports
latest=$(ls -t reports/*.json 2>/dev/null | grep -v '/last\.json$' | head -1)
[ -n "$latest" ] && cp "$latest" reports/last.json

sed "s/__HOST__/$PAVOIS_DEMO_HOST/g" "$PAVOIS_DEMO_TAPE" > "$tmp/pavois.tape"
(cd "$short" && vhs "$tmp/pavois.tape") 2>&1 | tail -3

for f in demo-pavois.mp4 demo-pavois-after.mp4; do
  [ -f "$f" ] && ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" |
    awk -v f="$f" '{printf "%s: %.0fs\n", f, $1}'
done

# Both acts present: join them into the file the site serves. Same encoder settings on both, so
# this is a stream copy, not a re-encode. Record act 1 against a FRESH VM and act 2 against that
# same VM once hardened; recording them in the other order would measure two different machines.
if [ -f demo-pavois.mp4 ] && [ -f demo-pavois-after.mp4 ]; then
  out=site/public/media/pavois-demo.mp4
  mkdir -p "$(dirname "$out")"
  list=$tmp/concat.txt
  printf "file '%s'\nfile '%s'\n" "$PWD/demo-pavois.mp4" "$PWD/demo-pavois-after.mp4" > "$list"
  if ffmpeg -v error -f concat -safe 0 -i "$list" -c copy "$out" -y; then
    ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" |
      awk -v f="$out" '{printf "%s: %.0fs\n", f, $1}'
  fi
fi
