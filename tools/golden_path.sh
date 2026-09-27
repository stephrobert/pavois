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
# The binary under test. Defaults to the one this checkout builds; PAVOIS_BIN points it at another,
# which is how a campaign can prove what a RELEASE does rather than what the working tree does.
# Those are not the same claim: the released artefact carries its own embedded rule base, and twice
# already a release shipped a binary whose behaviour no test in this repository had exercised.
PAV=${PAVOIS_BIN:-$PWD/go/pavois}

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
if [ -n "${PAVOIS_BIN:-}" ]; then
  # Provided from outside: do NOT build over it. Building would silently replace the artefact the
  # campaign was asked to judge with the working tree's, and the log would say nothing about it.
  [ -x "$PAV" ] || { echo "PAVOIS_BIN is not an executable: $PAV"; exit 1; }
  echo "binary provided: $PAV" | tee -a "$LOG"
else
  mise run build >/dev/null 2>&1 || { echo "build failed"; exit 1; }
fi
"$PAV" version | tee -a "$LOG"

step "1. a FRESH VM, created by the published tooling"
mise run vm -- down "$OS" >/dev/null 2>&1
# --sudo-password takes NO value: vm.py reads PAVOIS_SUDO_PASSWORD from the environment. Passing
# it here put the lab password into `ps` output for the whole run, on a machine where every user
# can read it, and this repository's own rule forbids exactly that.
# The reason is printed, not swallowed. This line used to end on `>/dev/null || { echo "VM creation
# failed"; exit 1; }`, so a refusal that explained itself perfectly well came out as four words:
#
#     vm: 4GiB would leave 5.7GiB for everything else on this machine (9.7GiB available now).
#         Free memory, stop other guests, or ask for less: --memory 3GiB
#
# became "VM creation failed". The project's own trap catalogue says never to do this on a step that
# can fail, and this is the step that fails when the machine is not the one you expected.
# PAVOIS_VM_MEMORY lets a campaign run on a machine that is already busy. vm.py refuses a guest
# that would leave the host under 6GiB, which is right and which also means a campaign cannot
# run at all on a workstation with a browser open unless the guest can be asked to be smaller.
VM_ARGS=(up "$OS" --sudo-password)
[ -n "${PAVOIS_VM_MEMORY:-}" ] && VM_ARGS+=(--memory "$PAVOIS_VM_MEMORY")
if ! run mise run vm -- "${VM_ARGS[@]}" > "$OUT/vm-up.log" 2>&1; then
  echo "VM creation failed. It said:"
  sed 's/^/    /' "$OUT/vm-up.log" | tail -8 | tee -a "$LOG"
  exit 1
fi
cat "$OUT/vm-up.log" >> "$LOG"
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

# A control that PASSED on the stock machine and FAILS after hardening is a defect, and this
# verdict used to swallow it. Four platforms shipped as VERIFIED for five days carrying three
# regressions each (rhel8/9/10) and one (fedora), counted in the bundle, named in the bundle, and
# absent from every line a human reads. See #372.
#
# It does not raise FAILURES. A campaign that improved 210 controls and broke 3 is not the same
# result as one that never ran, and turning the nightly red on all three RHEL platforms until #373
# lands would train everyone to ignore a red nightly. The verdict stops saying the clean word
# instead, which is the part that was untrue.
REGRESSED=""
if [ -f "$OUT/bundle/campaign-delta.json" ]; then
  REGRESSED=$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
print(" ".join((d.get("controls") or {}).get("pass>fail") or []))
' "$OUT/bundle/campaign-delta.json" 2>/dev/null)
fi

echo "  bootstrap refusal gate : $GATE" | tee -a "$LOG"
echo "  blocking failures      : $FAILURES" | tee -a "$LOG"
if [ -n "$REGRESSED" ]; then
  # shellcheck disable=SC2086
  set -- $REGRESSED
  echo "  hardening regressions  : $# ($REGRESSED)" | tee -a "$LOG"
else
  echo "  hardening regressions  : 0" | tee -a "$LOG"
fi
echo "  artefacts              : $OUT" | tee -a "$LOG"
echo "  destroy the VM with    : mise run vm -- down $OS" | tee -a "$LOG"
if [ "$FAILURES" -ne 0 ]; then
  echo "  GOLDEN PATH: FAILED" | tee -a "$LOG"
elif [ -n "$REGRESSED" ]; then
  echo "  GOLDEN PATH: PASSED WITH REGRESSIONS" | tee -a "$LOG"
else
  echo "  GOLDEN PATH: PASSED" | tee -a "$LOG"
fi
exit "$FAILURES"
