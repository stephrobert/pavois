#!/usr/bin/env bash
# The golden path, end to end, on a machine created by the published tooling.
#
#   tools/golden_path.sh [os]        # default: debian12
#
# This is the answer to "show me that Pavois actually works". A fresh VM, scanned, planned,
# hardened, rebooted, CONVERGED with a second pass, scanned again, diffed, and sealed into an
# evidence bundle that is then verified. Every artefact lands under reports/golden-<os>-<stamp>/.
#
# It is not a test in the unit sense. It is a demonstration that has to hold on a real machine,
# which is the only kind of proof a hardening tool can offer.
#
# Four things it asserts beyond the happy path, each because it was once false:
#
#   1. `harden apply` REFUSES to install the engine without --bootstrap-cinc. The claim is
#      "nothing installed behind your back"; this executes it. The install used to run
#      unconditionally, and before the confirmation prompt.
#   2. EVERY scan is checked for trustworthiness before its numbers are believed. Three families
#      of controls were once reporting verdicts they had never measured, and no stage noticed.
#   3. TWO passes. Hardening mutates the machine, so one pass cannot close the gaps it creates:
#      installing `at` creates /etc/at.deny, pulling in postfix brings a banner naming the distro,
#      sssd ships an AppArmor profile in complain mode. The second plan is REGENERATED from a
#      current scan, never replayed: a plan is a snapshot, and replaying it rewrites settings based
#      on a machine that no longer exists.
#   4. the host still answers SSH at the end. A hardening run that locks you out has not hardened
#      a machine, it has destroyed one.
#
# Requirements: incus, a key the VM trusts, and PAVOIS_SUDO_PASSWORD when the target account needs
# a password. The lab fleet does; a cloud image usually does not.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

OS=${1:-debian12}
KEY=${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=reports/golden-$OS-$STAMP
PAV=$PWD/go/pavois

mkdir -p "$OUT"/{before,pass1,pass2}
LOG=$OUT/campaign.log
: > "$LOG"
FAILURES=0

step() { printf '\n=== %s ===\n' "$*" | tee -a "$LOG"; }
run() { printf '$ %s\n' "$*" | tee -a "$LOG"; "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }
latest() { ls -t "$1"/*.json 2>/dev/null | head -1; }

# Trustworthiness gate. A scan whose controls measured nothing must never be read as a result, so
# this runs on EVERY scan, not just the last one. Errors are fatal to the campaign; warnings are
# printed and kept, because a real family of gaps (unpartitioned mounts) looks the same from here.
validate_scan() {
  local label=$1 file=$2
  [ -n "$file" ] || { echo "  no scan to validate ($label)"; FAILURES=$((FAILURES + 1)); return 1; }
  printf '  --- run validation: %s\n' "$label" | tee -a "$LOG"
  if run python3 tools/validate_run.py "$file"; then
    return 0
  fi
  echo "  RUN VALIDATION FAILED for $label: the scan reported verdicts it did not measure" | tee -a "$LOG"
  FAILURES=$((FAILURES + 1))
  return 1
}

step "0. the binary under test"
mise run build >/dev/null 2>&1 || { echo "build failed"; exit 1; }
"$PAV" version | tee -a "$LOG"

step "1. a FRESH VM, created by the published tooling"
mise run vm -- down "$OS" >/dev/null 2>&1
# --sudo-password takes NO value: vm.py reads PAVOIS_SUDO_PASSWORD from the environment. Passing
# it here put the lab password into `ps` output for the whole run, on a machine where every user
# can read it, and this repository's own rule forbids exactly that.
run mise run vm -- up "$OS" --sudo-password >/dev/null || {
  echo "VM creation failed"; exit 1; }
IP=$(mise run vm -- ip "$OS" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
[ -n "$IP" ] || { echo "no IP for $OS"; exit 1; }
T="pavois@$IP"
echo "  target: $T" | tee -a "$LOG"

step "2. GATE: apply must refuse to install the engine without consent"
run "$PAV" harden plan "$T" --key "$KEY" --sudo --enable auto --out "$OUT/plan1.yml" || exit 1
GATE=FAILED
if ! "$PAV" harden apply "$OUT/plan1.yml" --key "$KEY" --sudo --yes > "$OUT/refusal.txt" 2>&1; then
  grep -q 'bootstrap-cinc' "$OUT/refusal.txt" && GATE=ok || GATE=unclear
fi
echo "  bootstrap refusal: $GATE" | tee -a "$LOG"
[ "$GATE" = ok ] || { echo "  the engine was installed without being asked"; FAILURES=$((FAILURES + 1)); }

step "3. scan the stock machine, and check the scan itself"
run "$PAV" scan "$T" --key "$KEY" --sudo --format json --out "$OUT/before" || true
BEFORE=$(latest "$OUT/before")
validate_scan "stock machine" "$BEFORE"

step "4. PASS 1: apply the automatic class, reboot, re-scan"
run "$PAV" harden apply "$OUT/plan1.yml" --key "$KEY" --sudo --yes --bootstrap-cinc --reboot --scan || true
run "$PAV" scan "$T" --key "$KEY" --sudo --format json --out "$OUT/pass1" || true
P1=$(latest "$OUT/pass1")
validate_scan "after pass 1" "$P1"

step "5. PASS 2: re-plan from the CURRENT state, apply, reboot, re-scan"
# Regenerated, never replayed: pass 1 installed software, so the machine the first plan described
# is gone. Replaying it would rewrite settings from a state that no longer exists.
run "$PAV" harden plan "$T" --key "$KEY" --sudo --enable auto --out "$OUT/plan2.yml" || true
run "$PAV" harden apply "$OUT/plan2.yml" --key "$KEY" --sudo --yes --bootstrap-cinc --reboot --scan || true
run "$PAV" scan "$T" --key "$KEY" --sudo --format json --out "$OUT/pass2" || true
P2=$(latest "$OUT/pass2")
validate_scan "after pass 2" "$P2"

step "6. what two passes changed"
[ -n "${BEFORE:-}" ] && [ -n "${P2:-}" ] && run "$PAV" diff "$BEFORE" "$P2" || echo "  skipped"

step "7. what the SECOND pass alone changed"
[ -n "${P1:-}" ] && [ -n "${P2:-}" ] && run "$PAV" diff "$P1" "$P2" || echo "  skipped"

step "8. evidence bundle, and its verification"
if [ -n "${BEFORE:-}" ] && [ -n "${P2:-}" ]; then
  run "$PAV" bundle "$BEFORE" "$P2" --out "$OUT/bundle" || true
  run "$PAV" bundle verify "$OUT/bundle" || { echo "  BUNDLE VERIFICATION FAILED"; FAILURES=$((FAILURES + 1)); }
fi

step "9. the host is still reachable"
# -F /dev/null: a global ssh_config with a `Host *` ProxyJump breaks direct connections. Pavois
# neutralises it; a bare ssh does not, and fails with a misleading "UNKNOWN port 65535" that reads
# exactly like a host bricked by the hardening.
if ssh -F /dev/null -i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=no \
       -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15 "$T" \
       'echo "  ssh ok on $(hostname), up$(uptime -p | sed s/up//)"' 2>&1 | tee -a "$LOG" | grep -q 'ssh ok'; then
  :
else
  echo "  THE HOST IS UNREACHABLE after hardening" | tee -a "$LOG"
  FAILURES=$((FAILURES + 1))
fi

step "verdict"
echo "  bootstrap refusal gate : $GATE" | tee -a "$LOG"
echo "  blocking failures      : $FAILURES" | tee -a "$LOG"
echo "  artefacts              : $OUT" | tee -a "$LOG"
echo "  destroy the VM with    : mise run vm -- down $OS" | tee -a "$LOG"
[ "$FAILURES" -eq 0 ] && echo "  GOLDEN PATH: PASSED" | tee -a "$LOG" \
                      || echo "  GOLDEN PATH: FAILED" | tee -a "$LOG"
exit "$FAILURES"
