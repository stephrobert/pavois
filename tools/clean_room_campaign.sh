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

# This orchestrates YOUR Proxmox lab; it ships with NO topology baked in. Point it at your own
# hypervisor and fleet through the environment (or a local, untracked campaign.env):
#
#   PVE            ssh target of the Proxmox host        e.g. root@203.0.113.11
#   ISO            directory holding the cloud images    e.g. /var/lib/vz/template/iso
#   CK_GW          gateway of the VM subnet              e.g. 203.0.113.1
#   PAVOIS_SSH_FROM  CIDR allowed to reach the VMs       e.g. 203.0.113.0/24
#   PAVOIS_SUDO_PASSWORD  sudo password of the CK_USER account on the VMs (required, no default)
#   FLEET_FILE     path to a file of `os:vmid:ip:image` rows (one per line); required
#   PAVOIS_VMIDS   space-separated VMIDs this script is ALLOWED to destroy (safety allowlist)
#
# A sample fleet file lives at tools/clean_room_campaign.env.example. Real lab values (IPs, VMIDs,
# passwords) are NEVER committed: this is a public repo (see the repo hygiene rules in CONTRIBUTING).
[ -f campaign.env ] && . ./campaign.env

: "${PVE:?set PVE to your Proxmox ssh target, e.g. root@203.0.113.11 (never commit it)}"
: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD (no default; lab-only, never commit it)}"
: "${FLEET_FILE:?set FLEET_FILE to a file of os:vmid:ip:image rows (see .env.example)}"
: "${PAVOIS_VMIDS:?set PAVOIS_VMIDS to the space-separated VMIDs this script may destroy}"
ISO=${ISO:?set ISO to the cloud-image directory}
CK_GW=${CK_GW:?set CK_GW to the VM subnet gateway}
PAVOIS_SSH_FROM=${PAVOIS_SSH_FROM:?set PAVOIS_SSH_FROM to the CIDR allowed to reach the VMs}
LOGDIR=${LOGDIR:-/tmp/pavois-campaign}
mkdir -p "$LOGDIR"

# os:vmid:ip:image, read from your (untracked) FLEET_FILE. This script DESTROYS the VMID in each
# row, so PAVOIS_VMIDS is a hard allowlist and every VM is re-checked by name (pavois-*) below.
mapfile -t FLEET < <(grep -vE '^\s*(#|$)' "$FLEET_FILE")

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
  PVE=$PVE CK_VMID=$vmid CK_IP=$ip CK_GW=$CK_GW CK_OS=$os CK_USER=${CK_USER:-pavois} \
  CK_CLOUDIMG=$img CK_MEM=8192 CK_CORES=6 \
  PAVOIS_SUDO_PASSWORD=$PAVOIS_SUDO_PASSWORD PAVOIS_SSH_FROM=$PAVOIS_SSH_FROM \
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
