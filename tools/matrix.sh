#!/usr/bin/env bash
# Run the full hardening campaign across the supported OSes, one at a time, and print the table.
#
#   tools/matrix.sh                       every OS whose image is reachable
#   tools/matrix.sh debian13 rhel9        just those
#   MATRIX_KEEP=1 tools/matrix.sh rhel9   leave the VM up afterwards, to inspect it
#
# Serial, not parallel, and deliberately so. Each VM takes 4 GB and a kernel build wants ~20 GB of
# disk; two campaigns at once on a workstation means the pair fights for RAM and the slower one
# reports numbers that measure contention rather than hardening. Serial also keeps the output
# readable, which matters when the point is a table somebody will act on.
#
# For each OS: create a VM, wait for SSH, run tools/harden_validate.sh (scan, plan, enable every
# safe gap, apply, reboot, LOOP until a pass has nothing left to do), record the grades, delete the
# VM. A failure is recorded and the matrix carries on: the value is in the row that is missing as
# much as in the ones that are there.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD (it reaches cinc over stdin, never argv)}"
KEY="${MATRIX_KEY:-$HOME/.ssh/id_ed25519}"
KEEP="${MATRIX_KEEP:-}"
OUT="${MATRIX_OUT:-reports/matrix-$(date -u +%Y%m%d-%H%M).md}"

ALL=(debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2604 rhel8 rhel9 rhel10 fedora)
TARGETS=("${@:-${ALL[@]}}")
[ $# -gt 0 ] && TARGETS=("$@")

mkdir -p reports
: > "$OUT"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
row() { printf '| %-11s | %-10s | %-22s | %s |\n' "$1" "$2" "$3" "$4" >> "$OUT"; }

{
  echo "# Hardening matrix: $(date -u +'%Y-%m-%d %H:%M UTC')"
  echo
  echo "One VM at a time, created from a stock cloud image, hardened by pavois alone"
  echo "(scan, plan, enable every safe gap, apply, reboot, looped to a fixpoint)."
  echo
  echo "| OS | result | remediable posture | notes |"
  echo "|---|---|---|---|"
} >> "$OUT"

for os in "${TARGETS[@]}"; do
  say "$os: provisioning"
  if ! python3 tools/vm.py up "$os" --sudo-password "$PAVOIS_SUDO_PASSWORD" > "/tmp/matrix-$os.log" 2>&1; then
    reason=$(grep -m1 -E "^vm: " "/tmp/matrix-$os.log" | cut -c1-120)
    echo "  SKIPPED: ${reason:-provisioning failed}"
    row "$os" "skipped" "-" "${reason:-provisioning failed}"
    continue
  fi
  ip=$(python3 tools/vm.py ip "$os")
  echo "  up at $ip"

  say "$os: campaign"
  log="/tmp/matrix-$os-campaign.log"
  bash tools/harden_validate.sh "$os" "pavois@$ip" "$KEY" > "$log" 2>&1
  rc=$?

  # The harness prints the posture line after every scan; the LAST one is the outcome.
  # -a: the campaign log carries NUL bytes (ssh -tt), so grep calls it binary and prints nothing
  # without it. That is how ubuntu2204 converged to grade B and the table said "?".
  posture=$(grep -aoE "Remediable posture: grade [A-E] \([0-9]+/[0-9]+" "$log" | tail -1 | sed 's/Remediable posture: //')
  # There is only ONE posture measurement per campaign: harden_validate.sh pipes each scan
  # through `tail -3`, which keeps the final grade and drops the baseline one. So the table can
  # report where a system ENDS, not how far it moved. Saying "from grade ?" pretended otherwise.
  if [ "$rc" -eq 0 ]; then
    note="final posture; baseline not retained by the harness"
  else
    note=$(grep -am1 -E "^error:|FATAL:|command not found" "$log" | cut -c1-90)
  fi

  if [ "$rc" -eq 0 ]; then
    echo "  converged: ${posture:-?}"
    row "$os" "converged" "${posture:-?}" "${note:-}"
  else
    echo "  FAILED (exit $rc): ${note:-see $log}"
    row "$os" "failed ($rc)" "${posture:--}" "${note:-see $log}"
  fi

  if [ -z "$KEEP" ]; then
    python3 tools/vm.py down "$os" >/dev/null 2>&1
  else
    echo "  kept: $ip"
  fi
done

say "matrix written to $OUT"
cat "$OUT"
