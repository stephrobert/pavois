#!/usr/bin/env bash
# Issue #286, reproduced then closed, on ONE disposable VM.
#
# The reporter's brief is followed literally, because its value is in the order: the released
# binary first, so the defect is SEEN, then the fixed binary on the same machine, so the difference
# cannot be blamed on the environment. Two VMs would prove less.
#
#   "VM jetable, jamais un poste de travail : harden ecrit sur le systeme, et l'issue #206
#    signale deja qu'un plan installe cinc-auditor sur la cible."
#
# That constraint is why this is a script. `harden plan` is not read-only enough to aim at a
# workstation, and a verification retyped by hand is one that will one day be retyped at the wrong
# target. It happened in this very session.
#
# The witness, and why it matters: `scan` must succeed on the VM with the SAME released binary.
# That is what makes the rest conclusive. It rules out "the binary is broken" and "the engine is
# missing" and leaves exactly one explanation for harden failing.
#
# The test that discriminates: run it again from another directory. If the path in the error MOVES,
# the reference is resolved against the current directory, not against a fixed location or the
# embedded copy. That is the reporter's finding, and it is what this replays.
#
# Usage: tools/release/repro_286.sh [fixed-binary]   (default: build one from the working tree)
# The VM is deleted at the end, including on failure.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

VM=pavois-repro-286
RELEASE=${PAVOIS_VERSION:-v0.1.1}
REPO=stephrobert/pavois
FIXED=${1:-}
fails=0
say() { printf '%s\n' "$*"; }
ok()  { printf '  [ ok ] %s\n' "$1"; }
ko()  { printf '  [FAIL] %s\n         %s\n' "$1" "$2"; fails=$((fails + 1)); }

# pavois styles its own output, so `grade E` on screen is `grade \e[1mE\e[0m` in a pipe: the witness
# check went red on a scan that had plainly succeeded, and the detail line printed the grade it had
# just failed to find. Every match goes through this.
plain() { sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'; }

work=$(mktemp -d)
cleanup() {
  incus delete "$VM" --force >/dev/null 2>&1
  rm -rf "$work"
  say "VM deleted"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------- the fixed binary, built here
if [ -z "$FIXED" ]; then
  say "== build the fixed binary from the working tree (corpus AND reference embedded)"
  mise run embed:all >/dev/null 2>&1 || { say "embed failed"; exit 1; }
  ( cd go && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
      -ldflags="-s -w -X pavois/cmd.version=0.1.2-dev" -o "$work/pavois-fixed" . ) \
    || { say "go build failed"; exit 1; }
  FIXED="$work/pavois-fixed"
fi
say "  fixed:    $FIXED ($(stat -c%s "$FIXED") bytes)"

# ---------------------------------------------------------------- the released binary, as a user
say "== download the released binary, verified, exactly as the reporter did"
( cd "$work" && gh release download "$RELEASE" --repo "$REPO" \
    --pattern 'pavois-linux-amd64' --pattern 'checksums.txt' >/dev/null 2>&1 ) \
  || { say "could not download $RELEASE"; exit 1; }
( cd "$work" && sha256sum --ignore-missing --check checksums.txt ) | sed 's/^/  /'
if ( cd "$work" && gh attestation verify pavois-linux-amd64 --repo "$REPO" >/dev/null 2>&1 ); then
  say "  SLSA attestation: verified"
else
  say "  SLSA attestation: FAILED"
  fails=$((fails + 1))
fi
say "  released: $work/pavois-linux-amd64 ($(stat -c%s "$work/pavois-linux-amd64") bytes)"

# ---------------------------------------------------------------- the VM
say "== a fresh VM"
incus delete "$VM" --force >/dev/null 2>&1
# init + device + start, NOT launch + device + restart. The image has no NIC by default, and the
# reporter's brief adds it afterwards, which forces a restart: `incus restart` then waits for a
# clean ACPI shutdown the fresh VM does not give, and hangs for as long as you let it. Attaching
# the card before the first boot reaches the same state with no restart at all.
incus init images:ubuntu/24.04 "$VM" --vm -c limits.cpu=2 -c limits.memory=2GiB >/dev/null 2>&1 \
  || { say "could not create the VM"; exit 1; }
incus config device add "$VM" eth0 nic network=incusbr0 >/dev/null 2>&1
incus start "$VM" >/dev/null 2>&1 || { say "could not start the VM"; exit 1; }
# The agent takes about a minute to answer. Nothing here uses SSH; `incus exec` goes through it.
for _ in $(seq 1 72); do
  incus exec "$VM" -- true >/dev/null 2>&1 && break
  sleep 5
done
incus exec "$VM" -- true >/dev/null 2>&1 || { say "the agent never answered"; exit 1; }
say "  up"

incus file push "$work/pavois-linux-amd64" "$VM/root/pavois" >/dev/null 2>&1 || { say "push failed"; exit 1; }
incus exec "$VM" -- chmod +x /root/pavois

say "== install the engine (verified download, not a piped script)"
# --bootstrap-cinc does not do this on a local target, which is #283. Here it is done by hand, the
# way the installation page documents it.
#
# The output is NOT swallowed. Hiding it is how the previous run reported "could not install
# cinc-auditor" and nothing else, which says only that something went wrong somewhere.
cat > "$work/install-cinc.sh" <<'CINC'
set -e
command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }
META=$(curl -fsSL "https://omnitruck.cinc.sh/stable/cinc-auditor/metadata?p=ubuntu&pv=24.04&m=x86_64")
URL=$(printf '%s\n' "$META" | awk '/^url/ {print $2}')
SHA=$(printf '%s\n' "$META" | awk '/^sha256/ {print $2}')
[ -n "$URL" ] || { echo "omnitruck returned no url; metadata was:"; printf '%s\n' "$META"; exit 1; }
curl -fsSL "$URL" -o /tmp/cinc-auditor.deb
echo "$SHA  /tmp/cinc-auditor.deb" | sha256sum --check -
dpkg -i /tmp/cinc-auditor.deb >/dev/null
CINC
incus file push "$work/install-cinc.sh" "$VM/root/install-cinc.sh" >/dev/null 2>&1
if ! incus exec "$VM" -- bash /root/install-cinc.sh 2>&1 | sed 's/^/  /'; then
  say "could not install cinc-auditor (its own output is above)"
  exit 1
fi
incus exec "$VM" -- rm -f /root/install-cinc.sh
say "  cinc-auditor $(incus exec "$VM" -- cinc-auditor version 2>/dev/null | tail -1)"

# ---------------------------------------------------------------- helpers
plan_from() { # <dir> -> the command's output
  incus exec "$VM" -- bash -c "cd $1 && /root/pavois harden plan local --out /root/reports" 2>&1 | plain
}
# Here-strings, not pipes. Under `set -o pipefail`, `grep -q` exits on the first match and closes
# the pipe; the writer takes a SIGPIPE and pipefail reports the pipeline as FAILED although the
# match succeeded. It only bites once the output is large, which is why the witness check went red
# on a full scan report and passed on everything smaller.
is_cwd_relative() { # does the error name a path under the directory we ran from?
  grep -q "read reference: open ${1%/}/docs/reference" <<<"$2"
}
produced_a_plan() {
  grep -qiE 'remediation|plan written|controls? to|harden apply' <<<"$1"
}

# ---------------------------------------------------------------- 1. the witness
say ""
say "################ WITH THE RELEASED BINARY ($RELEASE)"
say "--- the witness: scan must succeed, or nothing below means anything"
out=$(incus exec "$VM" -- /root/pavois scan local --out /root/reports 2>&1 | plain)
if grep -qiE 'grade [A-E]' <<<"$out"; then
  ok "scan local produced a graded report ($(printf '%s' "$out" | grep -oiE 'grade [A-E]' | head -1))"
else
  ko "scan local did not produce a grade: the rest of this run proves nothing" \
     "$(printf '%s' "$out" | tail -3 | tr '\n' ' ' | cut -c1-200)"
fi

say ""
say "--- the defect: harden plan, from /root"
out_root=$(plan_from /root)
if grep -q 'read reference' <<<"$out_root"; then
  ok "reproduced: $(printf '%s' "$out_root" | grep 'read reference' | head -1 | cut -c1-90)"
else
  ko "the defect did NOT reproduce on the released binary" \
     "$(printf '%s' "$out_root" | tail -2 | tr '\n' ' ' | cut -c1-160)"
fi

say ""
say "--- the test that discriminates: the same command from /opt/essai"
incus exec "$VM" -- mkdir -p /opt/essai >/dev/null 2>&1
out_essai=$(plan_from /opt/essai)
if is_cwd_relative /root "$out_root" && is_cwd_relative /opt/essai "$out_essai"; then
  ok "the path FOLLOWED the working directory: resolved against the cwd, not a fixed location"
  say "         /root      -> $(printf '%s' "$out_root" | grep -o '/root/docs[^ ]*' | head -1)"
  say "         /opt/essai -> $(printf '%s' "$out_essai" | grep -o '/opt/essai/docs[^ ]*' | head -1)"
else
  ko "could not confirm the cwd-relative resolution" \
     "$(printf '%s' "$out_essai" | tail -2 | tr '\n' ' ' | cut -c1-160)"
fi

say ""
say "--- the contradiction the reporter cites"
doc=$(incus exec "$VM" -- /root/pavois doctor 2>&1 | plain | grep -i 'rule corpus')
say "         doctor says: $(printf '%s' "$doc" | tr -s ' ' | cut -c1-90)"
say "         and harden could not read a reference on the same binary."

# ---------------------------------------------------------------- 2. the fix, same machine
say ""
say "################ WITH THE FIXED BINARY, SAME VM"
incus file push "$FIXED" "$VM/root/pavois" >/dev/null 2>&1 || { say "push failed"; exit 1; }
incus exec "$VM" -- chmod +x /root/pavois
say "  $(incus exec "$VM" -- /root/pavois --version 2>&1 | head -1)"

say ""
say "--- harden plan must produce a plan, from every directory"
for dir in /root /opt/essai /; do
  out=$(plan_from "$dir")
  if grep -qE 'read reference|no hardening reference' <<<"$out"; then
    ko "harden plan still cannot read its reference from $dir" \
       "$(printf '%s' "$out" | grep -iE 'reference' | head -1 | cut -c1-120)"
  elif produced_a_plan "$out"; then
    ok "harden plan produced a plan from $dir"
  else
    ko "harden plan produced no plan from $dir" \
       "$(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
  fi
done

say ""
say "--- and nothing was dropped beside the binary to make that work"
if incus exec "$VM" -- test -e /root/docs 2>/dev/null || incus exec "$VM" -- test -e /docs 2>/dev/null; then
  ko "a docs/ tree exists on the VM" "the result would be meaningless: that is the file it used to need"
else
  ok "no docs/ tree anywhere: the reference came from inside the binary"
fi

say ""
if [ "$fails" -eq 0 ]; then
  say "#286: reproduced on $RELEASE, closed on the fixed binary, same machine."
else
  say "$fails check(s) failed."
fi
exit "$fails"
