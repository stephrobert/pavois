#!/usr/bin/env bash
# Run the clean-room proof for several OSes, two at a time.
#
# One OS at a time is honest but serial (~1h30 each); the hypervisor has 31 GB and only ~1 GB of
# swap, so three 8 GB builds at once get one of them OOM-killed. Two slots is what the box takes.
#
# Each OS goes through the same, unabridged path: fresh VM from the vendor cloud image -> KSPP
# kernel recipe -> LVM partition recipe -> converged `harden apply` -> invariants -> scan -> lynis.
# Nothing is done by hand: whatever comes out is what pavois produces on a machine nobody touched.
#
# Usage: tools/clean_room_campaign.sh [os ...]      (default: the six that need proving)
set -uo pipefail
cd "$(dirname "$0")/.."

PVE=${PVE:-root@192.168.10.11}
ISO=/var/lib/vz/template/iso
LOGDIR=${LOGDIR:-/tmp/pavois-campaign}
mkdir -p "$LOGDIR"

# os:vmid:ip:image
# VMIDs are pavois-only. 141-143 are the lab's saltminions and 150 is ascender-lab: this script
# DESTROYS the VMID it is given, so the range must never drift into someone else's machines.
FLEET=(
  "rhel9:140:192.168.10.70:$ISO/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
  "rhel8:131:192.168.10.71:$ISO/AlmaLinux-8-GenericCloud-latest.x86_64.qcow2"
  "rhel10:133:192.168.10.63:$ISO/AlmaLinux-10-GenericCloud-latest.x86_64.qcow2"
  "fedora:136:192.168.10.66:$ISO/fedora-42-cloud.qcow2"
  "ubuntu2604:138:192.168.10.68:$ISO/ubuntu-26.04-server-cloudimg-amd64.img"
  "ubuntu2204:139:192.168.10.69:$ISO/jammy-server-cloudimg-amd64.img"
)
PAVOIS_VMIDS="131 133 134 135 136 137 138 139 140"

want=("$@")
[ ${#want[@]} -eq 0 ] && want=(rhel9 rhel8 rhel10 fedora ubuntu2604 ubuntu2204)

run_one() {
  local os=$1 vmid=$2 ip=$3 img=$4 log="$LOGDIR/$os.log"
  # This function DESTROYS $vmid. The hypervisor is a shared lab: refuse anything that is not a
  # pavois VM, both by id and by name. A typo in a VMID must never cost someone else a machine.
  case " $PAVOIS_VMIDS " in *" $vmid "*) ;; *) echo "[$os] REFUSED: VM $vmid is not a pavois id"; return 1;; esac
  local name
  name=$(ssh "$PVE" "qm config $vmid 2>/dev/null | sed -n 's/^name: //p'")
  if [ -n "$name" ] && [[ "$name" != pavois-* ]]; then
    echo "[$os] REFUSED: VM $vmid is '$name', not a pavois VM — not touching it"
    return 1
  fi
  ssh "$PVE" "qm stop $vmid >/dev/null 2>&1; qm destroy $vmid --purge >/dev/null 2>&1" || true
  PVE=$PVE CK_VMID=$vmid CK_IP=$ip CK_GW=192.168.10.1 CK_OS=$os CK_USER=pavois \
  CK_CLOUDIMG=$img CK_MEM=8192 CK_CORES=6 \
  PAVOIS_SUDO_PASSWORD=${PAVOIS_SUDO_PASSWORD:-pavois} PAVOIS_SSH_FROM=192.168.10.0/24 \
    tools/clean_room_validate.sh all >"$log" 2>&1
  # the VM only needs to be scannable from here on: give the RAM back to the next build
  ssh "$PVE" "qm shutdown $vmid --timeout 90 >/dev/null 2>&1; sleep 10; \
              qm set $vmid --memory 3072 --cores 2 >/dev/null 2>&1; qm start $vmid >/dev/null 2>&1" || true
  local grade
  grade=$(grep -aoE "Grade [A-E]|Hardening index : [0-9]+|invariants OK|INVARIANT FAILED[^\"]*" "$log" | tr '\n' ' ')
  echo "[$os] ${grade:-NO RESULT — see $log}"
}

pids=()
for os in "${want[@]}"; do
  for row in "${FLEET[@]}"; do
    IFS=: read -r o v i m <<<"$row"
    [ "$o" = "$os" ] || continue
    while [ "$(jobs -rp | wc -l)" -ge 2 ]; do sleep 30; done   # two slots: the RAM the box has
    echo "== start $os (VM $v @ $i)"
    run_one "$o" "$v" "$i" "$m" &
    pids+=($!)
    sleep 20
  done
done
wait
echo "== campaign done; logs in $LOGDIR"
