#!/usr/bin/env bash
# The PUBLISHED binary, on a fresh VM, doing the job. Not a local build.
#
# This exists because two releases in a row shipped broken and every check passed. The checks ran
# against a binary built HERE, where `mise run embed:all` populates the embed directories. The
# artifact a user downloads is built by the release workflow, which populated one of the four and
# left three empty: v0.1.2 scans and cannot plan, list rules, report norms or emit OSCAL.
#
# So the subject of this script is the downloaded file and nothing else. It is deliberately not
# parameterised by a local path: there is no way to accidentally point it at a build.
#
# Usage: tools/release/verify_published_vm.sh [vX.Y.Z]     (default: the repository's latest)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

REPO=stephrobert/pavois
V=${1:-$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null)}
VM=pavois-published
fails=0
say() { printf '%s\n' "$*"; }
ok()  { printf '  [ ok ] %s\n' "$1"; }
ko()  { printf '  [FAIL] %s\n         %s\n' "$1" "$2"; fails=$((fails + 1)); }
plain() { sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'; }

work=$(mktemp -d)
# The VM is destroyed whatever happens, including a ctrl-C in the middle of the engine install:
# these run on the maintainer's own machine, beside their session.
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() { incus delete "$VM" --force >/dev/null 2>&1; rm -rf "$work"; say "VM deleted"; }
trap cleanup EXIT INT TERM

say "== the published $V, downloaded and verified as a user would"
( cd "$work" && gh release download "$V" --repo "$REPO" \
    --pattern 'pavois-linux-amd64' --pattern 'checksums.txt' >/dev/null 2>&1 ) \
  || { say "could not download $V"; exit 1; }
( cd "$work" && sha256sum --ignore-missing --check checksums.txt ) | sed 's/^/  /'
if ( cd "$work" && gh attestation verify pavois-linux-amd64 --repo "$REPO" >/dev/null 2>&1 ); then
  say "  SLSA attestation: verified"
else
  ko "the SLSA attestation did not verify" "$V"
fi
say "  $(stat -c%s "$work/pavois-linux-amd64") bytes"

say ""
say "== a fresh VM"
incus delete "$VM" --force >/dev/null 2>&1
# init + device + start, never launch + restart: `incus restart` on a fresh VM waits for an ACPI
# shutdown it will not get and hangs for as long as you let it.
incus init images:debian/13 "$VM" --vm -c limits.cpu=2 -c limits.memory=2GiB >/dev/null 2>&1 \
  || { say "could not create the VM"; exit 1; }
incus config device add "$VM" eth0 nic network=incusbr0 >/dev/null 2>&1
incus start "$VM" >/dev/null 2>&1 || { say "could not start the VM"; exit 1; }
for _ in $(seq 1 72); do incus exec "$VM" -- true >/dev/null 2>&1 && break; sleep 5; done
incus exec "$VM" -- true >/dev/null 2>&1 || { say "the agent never answered"; exit 1; }
vm()   { incus exec "$VM" -- bash -lc "$1" 2>&1 | plain; }
# shellcheck disable=SC2016  # $PRETTY_NAME is expanded inside the VM, not here
say "  $(vm '. /etc/os-release && echo "$PRETTY_NAME"' | tail -1)"

incus file push "$work/pavois-linux-amd64" "$VM/root/pavois" >/dev/null 2>&1 \
  || { say "push failed"; exit 1; }
incus exec "$VM" -- chmod +x /root/pavois

say ""
say "== the engine, installed by the documentation's own command"
cat > "$work/installer-cinc.sh" <<'CINC'
set -e
command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }
META=$(curl -fsSL "https://omnitruck.cinc.sh/stable/cinc-auditor/metadata?p=debian&pv=13&m=x86_64")
URL=$(printf '%s\n' "$META" | awk '/^url/ {print $2}')
SHA=$(printf '%s\n' "$META" | awk '/^sha256/ {print $2}')
[ -n "$URL" ] || { echo "omnitruck returned no url"; printf '%s\n' "$META"; exit 1; }
curl -fsSL "$URL" -o /tmp/cinc-auditor.deb
echo "$SHA  /tmp/cinc-auditor.deb" | sha256sum --check -
dpkg -i /tmp/cinc-auditor.deb >/dev/null
CINC
incus file push "$work/installer-cinc.sh" "$VM/root/installer-cinc.sh" >/dev/null 2>&1
incus exec "$VM" -- chmod +x /root/installer-cinc.sh
if timeout 900 incus exec "$VM" -- bash /root/installer-cinc.sh 2>&1 | tail -3 | sed 's/^/  /'; then
  ok "cinc-auditor $(vm 'cinc-auditor version' | tail -1)"
else
  ko "could not install the engine" "its output is above"
fi

# Each command, from / so nothing can be found beside the binary, and the whole point is what the
# PUBLISHED artifact carries.
probe() { # <label> <command> <what a broken binary says>
  out=$(vm "cd / && /root/pavois $2 2>&1" | grep -viE '^\s*$|██|╚|╔|═|Effective Linux')
  if printf '%s' "$out" | grep -qE 'embeds none|no hardening reference|no norm catalogue|no such file'; then
    ko "$1" "$(printf '%s' "$out" | grep -i error | head -1 | cut -c1-120)"
  elif [ "$(printf '%s' "$out" | wc -c)" -lt "${4:-200}" ]; then
    ko "$1: almost no output" "$(printf '%s' "$out" | tail -1 | cut -c1-110)"
  else
    ok "$1 ($(printf '%s' "$out" | wc -c) bytes)"
  fi
}

say ""
say "== what the published binary can actually do"
probe "pavois profiles lists the embedded corpus" "profiles"
probe "pavois rules reads the reference"          "rules --os debian13"
probe "pavois norms reads the catalogue"          "norms"
probe "pavois oscal emits the catalogue"          "oscal"

say ""
say "== and the scan, which is the half that worked in v0.1.2"
out=$(vm 'cd / && /root/pavois scan local --sudo --out /root/reports 2>&1 | tail -20')
if printf '%s' "$out" | grep -qiE 'grade [a-e]'; then
  ok "scan local graded the host ($(printf '%s' "$out" | grep -oiE 'grade [a-e]' | head -1))"
else
  ko "scan local produced no grade" "$(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
fi

say ""
say "== harden plan, the command #286 was filed about"
out=$(vm 'cd / && /root/pavois harden plan local --out /root/reports 2>&1 | tail -20')
if printf '%s' "$out" | grep -qE 'read reference|no hardening reference'; then
  ko "harden plan cannot read its reference (#286)" \
     "$(printf '%s' "$out" | grep -iE 'reference' | head -1 | cut -c1-120)"
elif printf '%s' "$out" | grep -qiE 'remediation|plan|control'; then
  ok "harden plan produced a plan from /"
else
  ko "harden plan produced no plan" "$(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
fi

say ""
if [ "$fails" -eq 0 ]; then
  say "the published $V does its job on a machine that had nothing."
else
  say "$fails check(s) failed on the PUBLISHED $V: this is what a user gets."
fi
exit "$fails"
