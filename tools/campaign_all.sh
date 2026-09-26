#!/usr/bin/env bash
# Run the golden-path campaign on every supported system, ONE VM AT A TIME.
#
#   PAVOIS_SUDO_PASSWORD=... tools/campaign_all.sh [os ...]
#
# With no argument it runs every system under profiles/linux/ that has no campaign matching the
# CURRENT corpus, which is the set `tools/release/evidence.py --all` reports as anything other than
# VERIFIED. Naming systems explicitly overrides that.
#
# WHY A DRIVER AND NOT A LOOP IN A SHELL
#
# Three constraints, each of which has already been broken here by hand:
#
#   1. ONE VM AT A TIME. These run on the maintainer's workstation, next to their session. Two
#      4 GiB guests and a kernel build will take the machine down. The driver refuses to start a
#      campaign when the host does not have the memory for it, and destroys each guest before the
#      next one is created.
#   2. THE GUEST IS ALWAYS DESTROYED. golden_path.sh prints the `down` command and leaves the VM
#      running on purpose, so a failure can be inspected. Across nine systems that is nine live
#      guests. The trap here closes them on exit, on interrupt, and on kill.
#   3. A FAILING CAMPAIGN IS DATA, NOT AN ABORT. The whole point of #351 is that FAILED and
#      INCOMPLETE are publishable states. Stopping the run at the first red system would hide the
#      other six, which is the behaviour the issue exists to end.
#
# The sudo password is read from the environment and never appears on a command line: `ps` is
# world-readable, and this is a lab credential on a machine that also carries real ones.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD (the lab VM sudo password) in the environment}"
export PAVOIS_SUDO_PASSWORD

# A guest wants 4 GiB, the host needs to keep working. Below this the driver waits rather than
# starting a campaign that will be killed halfway through and publish INCOMPLETE for no reason.
MIN_AVAIL_GB=${MIN_AVAIL_GB:-6}
MIN_DISK_GB=${MIN_DISK_GB:-40}

STAMP=$(date +%Y%m%d-%H%M%S)
OUT=reports/campaign-all-$STAMP
mkdir -p "$OUT"
PROGRESS=$OUT/progress.txt
CURRENT=""

cleanup() {
  if [ -n "$CURRENT" ]; then
    echo "  destroying $CURRENT" | tee -a "$PROGRESS"
    mise run vm -- down "$CURRENT" >/dev/null 2>&1
    CURRENT=""
  fi
}
trap cleanup EXIT INT TERM

avail_gb() { free -g | awk '/^Mem:/ {print $7}'; }
disk_gb() { df -BG --output=avail / | tail -1 | tr -dc '0-9'; }

if [ "$#" -gt 0 ]; then
  SYSTEMS=("$@")
else
  # Everything the evidence matrix does not already call VERIFIED. Read from the same state machine
  # the site will publish, so the driver and the matrix can never disagree about what is missing.
  mapfile -t SYSTEMS < <(
    python3 tools/release/evidence.py --all --json - 2>/dev/null |
      python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(p["os"] for p in d["platforms"] if p["state"] != "VERIFIED"))'
  )
fi

if [ "${#SYSTEMS[@]}" -eq 0 ]; then
  echo "campaign-all: every system is already VERIFIED against the current corpus."
  exit 0
fi

{
  echo "campaign-all $STAMP"
  echo "systems: ${SYSTEMS[*]}"
  echo "host: $(avail_gb) GiB available, $(disk_gb) GiB free on /"
  echo
} | tee -a "$PROGRESS"

# The binary under test is the one that will run on every guest. Build it once, here, rather than
# letting each campaign race to build it.
mise run build >/dev/null 2>&1 || { echo "campaign-all: build failed" | tee -a "$PROGRESS"; exit 1; }

declare -A RESULT
for os in "${SYSTEMS[@]}"; do
  [ -d "profiles/linux/$os" ] || { RESULT[$os]="no-such-profile"; continue; }

  waited=0
  while [ "$(avail_gb)" -lt "$MIN_AVAIL_GB" ]; do
    [ "$waited" -eq 0 ] && echo "waiting for memory ($(avail_gb) GiB < $MIN_AVAIL_GB)" | tee -a "$PROGRESS"
    waited=$((waited + 30))
    sleep 30
    if [ "$waited" -ge 900 ]; then
      RESULT[$os]="skipped-no-memory"
      break
    fi
  done
  [ "${RESULT[$os]:-}" = "skipped-no-memory" ] && continue

  if [ "$(disk_gb)" -lt "$MIN_DISK_GB" ]; then
    RESULT[$os]="skipped-no-disk"
    continue
  fi

  start=$SECONDS
  echo "=== $os  (started $(date +%H:%M:%S), $(avail_gb) GiB avail) ===" | tee -a "$PROGRESS"
  CURRENT=$os
  bash tools/golden_path.sh "$os" > "$OUT/$os.log" 2>&1
  rc=$?
  cleanup
  took=$(( (SECONDS - start) / 60 ))

  verdict=$(grep -oE 'GOLDEN PATH: [A-Z]+' "$OUT/$os.log" | tail -1)
  RESULT[$os]="${verdict:-no-verdict} (rc=$rc, ${took}m)"
  echo "  -> ${RESULT[$os]}" | tee -a "$PROGRESS"
done

{
  echo
  echo "=== campaign-all summary ==="
  for os in "${SYSTEMS[@]}"; do
    printf '  %-12s %s\n' "$os" "${RESULT[$os]:-not reached}"
  done
  echo
  echo "The matrix these campaigns feed:"
} | tee -a "$PROGRESS"

python3 tools/release/evidence.py --all 2>&1 | tee -a "$PROGRESS"
echo
echo "logs: $OUT/"
