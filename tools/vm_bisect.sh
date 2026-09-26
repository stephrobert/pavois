#!/usr/bin/env bash
# Find which of vm.py's launch settings stops a guest from booting on a hosted runner.
#
# The nightly campaign's guest reboots every five seconds there and never answers. The console says
# so plainly:
#
#     Loading Linux 6.1.0-53-amd64 ...
#     [FAILED] Failed unmounting run-incu...gent.mount - /run/incus_agent.
#     [    5.454542] watchdog: watchdog0: watchdog did not stop!
#     [    5.576437] reboot: Restarting system
#
# The same image boots in 29 seconds on the maintainer's machine with the same settings, and
# tools/release/scenario.sh has been booting VMs on these runners for weeks with a shorter list of
# settings. So this adds that list back one item at a time and reports which addition kills it.
#
# A variant PASSES when the incus agent answers. The agent speaks over vsock, so it needs no address
# and no DHCP: it is the earliest honest sign that the guest came up and stayed up.
#
# WHY A SECOND ATTEMPT
#
# The first version of this script reported that security.secureboot=false killed the guest. It does
# not: two guests carrying exactly that setting came up in 20 seconds each, seconds later, on the
# same machine. One flaky verdict is enough to send an investigation into the wrong wall, and this
# script exists precisely to be believed, so a variant only counts as DEAD when it fails twice.
#
# Every guest is destroyed before the next one is created, including on interrupt: nine dead guests
# is how a runner runs out of disk.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# Two things can be bisected here, and the first run settled which one matters.
#
#   MODE=settings   vm.py's launch flags, one at a time (the first question asked)
#   MODE=images     the image, with ONE minimal set of flags (the question that remains)
#
# The settings run came back with every variant dead, baseline included, and baseline is 2 vCPU and
# 2GiB with nothing added: essentially what tools/release/scenario.sh launches, nightly, green, on
# this same runner. So the cause is not in the flags, and only two differences with scenario.sh are
# left: the image, and the agent:config disk this script attaches and scenario.sh does not.
MODE=${MODE:-images}
IMAGE=${IMAGE:-images:debian/12/cloud}
BUDGET=${BUDGET:-120}          # seconds per attempt; a healthy guest answers in well under a minute
OUT=bisect
mkdir -p "$OUT"

CURRENT=""
cleanup() {
  if [ -n "$CURRENT" ]; then
    incus delete "$CURRENT" --force >/dev/null 2>&1
    CURRENT=""
  fi
}
trap cleanup EXIT INT TERM

# The cloud-init vm.py sends, reduced to what could plausibly reboot a machine: it updates the
# package index, installs a package and creates a user.
USERDATA="#cloud-config
package_update: true
packages:
  - openssh-server
users:
  - name: pavois
    groups: [sudo, wheel]
    sudo: \"ALL=(ALL) NOPASSWD:ALL\"
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null)
ssh_pwauth: false"

# Each variant adds ONE thing to the one above it, so the first that dies names the setting that did
# it. Built as arrays rather than a string: cloud-init user-data is multi-line YAML and any
# word-splitting scheme mangles it into "too many arguments", which is how the first run of this
# script lost that variant entirely.
variant_args() {
  local -n out=$2
  out=(-c limits.cpu=2 -c limits.memory=2GiB)
  case $1 in
    baseline) ;;
    mem4g) out=(-c limits.cpu=2 -c limits.memory=4GiB) ;;
    disk20g) out=(-c limits.cpu=2 -c limits.memory=4GiB -d root,size=20GiB) ;;
    secureboot-off)
      out=(-c limits.cpu=2 -c limits.memory=4GiB -d root,size=20GiB -c security.secureboot=false) ;;
    cloudinit)
      out=(-c limits.cpu=2 -c limits.memory=4GiB -d root,size=20GiB -c security.secureboot=false
           -c "cloud-init.user-data=$USERDATA") ;;
    nic-at-init)
      out=(-c limits.cpu=2 -c limits.memory=4GiB -d root,size=20GiB -c security.secureboot=false
           -c "cloud-init.user-data=$USERDATA" -n incusbr0) ;;
    # MODE=images: every image gets the SAME minimal flags, so the image is the only variable.
    *) out=(-c limits.cpu=2 -c limits.memory=2GiB) ;;
  esac
}

# MODE=images. `control` is the image tools/release/scenario.sh launches on this very runner every
# night, green: without a known-good control a bisection cannot tell "this image is broken" from
# "this harness is broken on this host", and this script has already been wrong once in exactly
# that way. `no-agent-disk` re-runs the dead image without the agent:config device, which is the
# only other thing scenario.sh does differently.
variant_image() {
  case $1 in
    control) echo "images:ubuntu/24.04" ;;
    deb12-cloud | no-agent-disk) echo "images:debian/12/cloud" ;;
    deb12-plain) echo "images:debian/12" ;;
    noble-cloud) echo "images:ubuntu/noble/cloud" ;;
    *) echo "$IMAGE" ;;
  esac
}

# One attempt. Returns 0 when the agent answers, and leaves its evidence in $OUT.
attempt() {
  # One assignment per line: `local a=$1 b="x-$a"` expands every argument BEFORE assigning any of
  # them, so the second would read an unbound variable and, under set -u, take the whole function
  # down. That is how the first run of this rewrite reported every variant DEAD at once.
  local name=$1
  local try=$2
  local vm="bisect-$name-$try"
  local args=()
  local img
  variant_args "$name" args
  img=$(variant_image "$name")
  CURRENT=$vm
  local log="$OUT/$name.$try.log"
  echo "image: $img" > "$log"

  if ! incus init "$img" "$vm" --vm "${args[@]}" >> "$log" 2>&1; then
    echo "init failed: $(tail -1 "$log")"
    cleanup
    return 2
  fi
  # Only when the variant did not already ask for one at creation.
  printf '%s\n' "${args[@]}" | grep -qx -- '-n' || \
    incus config device add "$vm" eth0 nic network=incusbr0 >> "$log" 2>&1
  # scenario.sh does NOT attach this, and scenario.sh boots here. One variant leaves it off so the
  # difference is measured rather than argued about.
  [ "$name" = no-agent-disk ] || \
    incus config device add "$vm" agent disk source=agent:config >> "$log" 2>&1
  if ! incus start "$vm" >> "$log" 2>&1; then
    echo "start failed: $(tail -1 "$log")"
    cleanup
    return 2
  fi

  local s=$SECONDS
  while [ $((SECONDS - s)) -lt "$BUDGET" ]; do
    if incus exec "$vm" -- true >/dev/null 2>&1; then
      echo "agent answered in $((SECONDS - s))s"
      cleanup
      return 0
    fi
    sleep 5
  done

  # What a guest that never answers still has to say. Attaching never returns, so it is read through
  # a pty under a timeout; whatever it printed by then is the evidence.
  local state console reboots
  state=$(incus info "$vm" 2>&1 | awk -F': *' '/^Status/ {print $2}' | tr -d '[:space:]')
  console="$OUT/$name.$try.console.log"
  timeout 20 script -qec "incus console $vm" /dev/null > "$console" 2>&1
  reboots=$(grep -c 'reboot: Restarting system' "$console" 2>/dev/null | head -1)
  echo "no agent in $((SECONDS - s))s, status=${state:-unknown}, ${reboots:-0} reboot(s) on console"
  cleanup
  return 1
}

case $MODE in
  settings) NAMES=(baseline mem4g disk20g secureboot-off cloudinit nic-at-init) ;;
  images) NAMES=(control deb12-cloud no-agent-disk deb12-plain noble-cloud) ;;
  *) echo "vm_bisect: MODE must be settings or images, not '$MODE'" >&2; exit 2 ;;
esac

echo "mode: $MODE, budget: ${BUDGET}s per attempt" | tee "$OUT/summary.txt"
printf '%-16s %-8s %s\n' VARIANT RESULT DETAIL | tee -a "$OUT/summary.txt"
printf '%-16s %-8s %s\n' '----------------' '--------' '------' | tee -a "$OUT/summary.txt"

dead_found=no
control_up=unknown
for name in "${NAMES[@]}"; do
  detail=$(attempt "$name" 1)
  rc=$?
  if [ $rc -ne 0 ]; then
    # Once is chance. The retry is what makes a DEAD worth acting on.
    detail2=$(attempt "$name" 2)
    rc2=$?
    if [ $rc2 -eq 0 ]; then
      printf '%-16s %-8s %s\n' "$name" "FLAKY" "first: $detail / retry: $detail2" \
        | tee -a "$OUT/summary.txt"
      continue
    fi
    dead_found=yes
    [ "$name" = control ] && control_up=no
    printf '%-16s %-8s %s\n' "$name" "DEAD" "$detail / again: $detail2" | tee -a "$OUT/summary.txt"
    continue
  fi
  [ "$name" = control ] && control_up=yes
  printf '%-16s %-8s %s\n' "$name" "UP" "$detail" | tee -a "$OUT/summary.txt"
done

{
  echo
  # The control is the image scenario.sh boots here nightly. If it dies too, this harness is
  # measuring itself and nothing below it means anything. Saying so is the whole reason it is here.
  if [ "$control_up" = no ]; then
    echo "CONTROL DEAD: the image that boots here every night did not. This run measured the"
    echo "harness, not the images, and no verdict below the control line can be trusted."
  elif [ "$dead_found" = yes ]; then
    echo "The control booted, so the DEAD lines are about their images, not about this host."
  else
    # A bisection that finds nothing is a result, and a loud one.
    echo "NOTHING FAILED TWICE: every variant booted here, so the cause is not in what was varied."
  fi
} | tee -a "$OUT/summary.txt"
