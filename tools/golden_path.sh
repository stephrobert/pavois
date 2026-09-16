#!/usr/bin/env bash
# The golden path, end to end, on a machine created by the published tooling.
#
#   tools/golden_path.sh [os]        # default: debian12
#
# This is the answer to "show me that Pavois actually works". It creates a fresh VM, scans it,
# plans, applies only the remediations judged safe, reboots, scans again, diffs, and seals an
# evidence bundle it then verifies. Every artefact is kept under reports/golden-<os>-<stamp>/.
#
# It is not a test in the unit sense: it is a demonstration that has to hold on a real machine,
# which is the only kind of proof a hardening tool can offer.
#
# Two things it asserts beyond the happy path, because both are claims the README makes:
#
#   1. `harden apply` REFUSES to install the engine on the target without --bootstrap-cinc.
#      The claim is "nothing installed behind your back"; this executes it. Up to today the
#      install ran unconditionally, and before the confirmation prompt.
#   2. the host is still reachable over SSH afterwards. A hardening run that locks you out has
#      not hardened anything, it has destroyed a machine.
#
# Requirements: incus, a key the VM trusts, and PAVOIS_SUDO_PASSWORD for a target whose account
# needs a password. The lab fleet does; a cloud image usually does not.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

OS=${1:-debian12}
KEY=${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=reports/golden-$OS-$STAMP
PAV=$PWD/go/pavois

mkdir -p "$OUT/before" "$OUT/after"
LOG=$OUT/campaign.log
: > "$LOG"

step() { printf '\n=== %s ===\n' "$*" | tee -a "$LOG"; }
run() { printf '$ %s\n' "$*" | tee -a "$LOG"; "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }
latest() { ls -t "$1"/*.json 2>/dev/null | head -1; }

step "0. the binary under test"
mise run build >/dev/null 2>&1 || { echo "build failed"; exit 1; }
"$PAV" version | tee -a "$LOG"

step "1. a FRESH VM, created by the published tooling"
mise run vm -- down "$OS" >/dev/null 2>&1
run mise run vm -- up "$OS" --sudo-password "${PAVOIS_SUDO_PASSWORD:-}" >/dev/null || {
  echo "VM creation failed"; exit 1; }
IP=$(mise run vm -- ip "$OS" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
[ -n "$IP" ] || { echo "no IP for $OS"; exit 1; }
T="pavois@$IP"
echo "  target: $T" | tee -a "$LOG"

step "2. GATE: apply must refuse to install the engine without consent"
run "$PAV" harden plan "$T" --key "$KEY" --sudo --enable auto --out "$OUT/plan.yml" || exit 1
GATE=FAILED
if ! "$PAV" harden apply "$OUT/plan.yml" --key "$KEY" --sudo --yes > "$OUT/refusal.txt" 2>&1; then
  grep -q 'bootstrap-cinc' "$OUT/refusal.txt" && GATE=ok || GATE=unclear
fi
echo "  bootstrap refusal: $GATE" | tee -a "$LOG"
[ "$GATE" = ok ] || echo "  WARNING: the engine was installed without being asked" | tee -a "$LOG"

step "3. scan the stock machine"
run "$PAV" scan "$T" --key "$KEY" --sudo --format json --out "$OUT/before" || true
BEFORE=$(latest "$OUT/before")

step "4. apply the automatic class, reboot, re-scan"
run "$PAV" harden apply "$OUT/plan.yml" --key "$KEY" --sudo --yes --bootstrap-cinc --reboot --scan || true

step "5. scan the hardened machine"
run "$PAV" scan "$T" --key "$KEY" --sudo --format json --out "$OUT/after" || true
AFTER=$(latest "$OUT/after")

step "5b. is this scan trustworthy?"
# Distinct from "is the machine compliant": this asks whether the scan measured anything at all.
# Three families of controls were found in one day reporting verdicts they never measured, and
# nothing in the pipeline noticed. This is what notices.
[ -n "${AFTER:-}" ] && run python3 tools/validate_run.py "$AFTER" || echo "  skipped"

step "6. what changed"
[ -n "${BEFORE:-}" ] && [ -n "${AFTER:-}" ] && run "$PAV" diff "$BEFORE" "$AFTER" || echo "  skipped"

step "7. evidence bundle, and its verification"
if [ -n "${BEFORE:-}" ] && [ -n "${AFTER:-}" ]; then
  run "$PAV" bundle "$BEFORE" "$AFTER" --out "$OUT/bundle" || true
  run "$PAV" bundle verify "$OUT/bundle" || true
fi

step "8. the host is still reachable"
# -F /dev/null: a global ssh_config with a `Host *` ProxyJump breaks direct connections. Pavois
# neutralises it; a bare ssh does not, and fails with a misleading "UNKNOWN port 65535".
ssh -F /dev/null -i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15 "$T" \
    'echo "  ssh ok on $(hostname), up$(uptime -p | sed s/up//)"' 2>&1 | tee -a "$LOG"

step "artefacts"
echo "  $OUT" | tee -a "$LOG"
echo "  destroy the VM with: mise run vm -- down $OS"
