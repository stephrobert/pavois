#!/usr/bin/env bash
# Pavois: CLEAN-ROOM end-to-end validation: provision a FRESH VM from the Ubuntu cloud
# image, then run the exact operator pipeline with nothing done by hand:
#   1 provision (Incus by default, Proxmox optional)  2 KSPP kernel build (delivered recipe)
#   3 LVM partitions (delivered recipe)        4 harden apply -> reboot -> scan + lynis
# The grade + lynis it prints are the honest, reproducible pavois result: a fresh box in,
# a hardened box out, no manual interventions. This is the machine behind "the result must
# be produced by pavois".
#
# Env: PAVOIS_SUDO_PASSWORD (sudo pw of the ci user). Usage:
#   tools/clean_room_validate.sh [stage]   stage = all|provision|kernel|partition|harden
#
# Provider: CK_PROVIDER=incus (default) provisions on THIS machine with tools/vm.py, which is what
# the project actually has. CK_PROVIDER=proxmox keeps the original path, and needs a Proxmox host
# with `qm`; the lab it was written for no longer exists, so that path is unverified.
set -euo pipefail
STAGE="${1:-all}"
# All infra targets come from the environment so no lab specifics live in the repo. Defaults use
# RFC-5737 documentation addresses; export the real ones for a run, e.g.
#   PVE=root@pve.example CK_IP=203.0.113.62 CK_GW=203.0.113.1 PAVOIS_SUDO_PASSWORD=... \
#     tools/clean_room_validate.sh all
PROVIDER="${CK_PROVIDER:-incus}"                                # incus (this machine) | proxmox
PVE="${PVE:-root@pve.example}"                                  # Proxmox host (ssh target)
VMID="${CK_VMID:-9000}"; IP="${CK_IP:-203.0.113.62}"; GW="${CK_GW:-203.0.113.1}"
OS="${CK_OS:-ubuntu2404}"; CIUSER="${CK_USER:-pavois}"
# the KSPP build is the memory-hungry step; size the VM for the hypervisor you have
MEM="${CK_MEM:-12288}"; CORES="${CK_CORES:-8}"
CLOUDIMG="${CK_CLOUDIMG:-/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img}"
KEY="${CK_KEY:-$HOME/.ssh/id_ed25519}"; TARGET=$CIUSER@$IP
# Running a single stage against an Incus VM that already exists: ask the provisioner where it is,
# rather than making the operator paste an address that changes on every rebuild. provision_incus
# overwrites both anyway when it creates one.
if [ "$PROVIDER" = incus ] && [ -z "${CK_IP:-}" ]; then
  _ip=$(python3 "$(dirname "$0")/vm.py" ip "$OS" 2>/dev/null || true)
  [ -n "$_ip" ] && { IP=$_ip; TARGET=$CIUSER@$IP; }
fi
: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD}"
pssh(){ ssh -o StrictHostKeyChecking=no "$PVE" "$@"; }
# Same -F /dev/null as vssh, and for the same reason: a global `Host *` ProxyJump in the
# operator ssh_config silently reroutes a direct transfer to a jump host with no route to
# the lab. This cost a 40-minute kernel build once, failing on "connection timed out" against
# an address that appears nowhere in this script.
vscp(){ scp -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY" "$1" "$TARGET:$2" >/dev/null; }
vssh(){ ssh -tt -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY" "$TARGET" "$@"; }
vrun(){ vssh "echo '$PAVOIS_SUDO_PASSWORD' | sudo -S bash -c '$1'"; }   # run as root on the VM
say(){ printf '\n\033[1;35m######## %s ########\033[0m\n' "$*"; }
waitssh(){ local n=0; until ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i "$KEY" "$TARGET" true 2>/dev/null; do sleep 5; n=$((n+1)); if [ $n -gt 180 ]; then echo "TIMEOUT waiting for $TARGET"; return 1; fi; done; return 0; }

# This script DESTROYS $VMID before recreating it. The hypervisor is a shared lab: a VMID picked
# without looking is a machine someone else loses, and `--purge` leaves nothing to restore. So we
# look FIRST, and destroy only what pavois itself created (a `pavois-*` name). A free id is fine,
# an occupied one is not: no matter how convenient the number was.
assert_ours(){
  local name
  name=$(pssh "qm config $VMID 2>/dev/null | sed -n 's/^name: //p'" | tr -d '\r')
  [ -z "$name" ] && return 0                                   # free id: nothing to destroy
  case "$name" in
    pavois-*) return 0 ;;                                      # ours, from a previous run
    *) echo "REFUSING: VM $VMID is '$name': not a pavois VM. Pick a free VMID (CK_VMID)." >&2
       exit 1 ;;
  esac
}

provision_incus(){
  say "1 PROVISION fresh $OS VM on Incus (this machine)"
  # tools/vm.py refuses containers by construction: 259 controls read kernel state, and inside a
  # container they would report on THIS workstation instead of the target.
  python3 tools/vm.py down "$OS" >/dev/null 2>&1 || true      # a clean room starts empty
  python3 tools/vm.py up "$OS" --memory "${CK_MEM_INCUS:-12GiB}" --disk "${CK_DISK:-40GiB}" \
      --cpu "$CORES" --sudo-password "$PAVOIS_SUDO_PASSWORD" >&2 || return 1
  IP=$(python3 tools/vm.py ip "$OS") || return 1
  [ -n "$IP" ] || { echo "provision: the VM has no address" >&2; return 1; }
  TARGET=$CIUSER@$IP
  say "VM is up at $IP"
  # Substrate normalization, NOT hardening: a real server is patched, and its sudo asks for a
  # password. vm.py --sudo-password already did the second half.
  vrun "cloud-init status --wait >/dev/null 2>&1 || true"
  vrun "if command -v apt-get >/dev/null; then export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get -y -qq upgrade; elif command -v dnf >/dev/null; then dnf -y -q upgrade || true; fi" 2>&1 | tail -2
  vrun "systemctl reboot" || true; sleep 8; waitssh
}

provision(){
  if [ "$PROVIDER" = incus ]; then provision_incus; return $?; fi
  say "1 PROVISION fresh $OS VM $VMID @ $IP (from cloud image, Proxmox)"
  assert_ours
  # push my pubkey to Proxmox for cloud-init
  scp -o StrictHostKeyChecking=no "${KEY}.pub" "$PVE:/root/pavois-ck.pub" >/dev/null
  rm -f /tmp/ck-known
  pssh "qm status $VMID >/dev/null 2>&1 && { qm stop $VMID --skiplock >/dev/null 2>&1; sleep 3; qm destroy $VMID --purge --destroy-unreferenced-disks 1; }; true"
  pssh "qm create $VMID --name pavois-$OS-clean --memory $MEM --cores $CORES --cpu host \
      --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single --agent 1 --serial0 socket --vga std --ostype l26"
  pssh "qm set $VMID --scsi0 srv-pve:0,import-from=$CLOUDIMG,discard=on"
  pssh "qm disk resize $VMID scsi0 50G"
  pssh "qm set $VMID --ide2 srv-pve:cloudinit"
  pssh "qm set $VMID --ciuser $CIUSER --cipassword $PAVOIS_SUDO_PASSWORD --sshkeys /root/pavois-ck.pub \
      --ipconfig0 ip=$IP/24,gw=$GW --nameserver '8.8.8.8 1.1.1.1'"
  pssh "qm set $VMID --scsi1 srv-pve:20 --boot order=scsi0"
  pssh "qm start $VMID"
  say "waiting for SSH on $IP"; waitssh
  vssh "echo booted: \$(uname -r); . /etc/os-release; echo \$PRETTY_NAME"
  # substrate normalization (NOT hardening): a real server is patched and has no cloud-init
  # NOPASSWD. pavois still sudos with a password via PAVOIS_SUDO_PASSWORD.
  say "substrate: apt upgrade + drop cloud-init NOPASSWD"
  vrun "cloud-init status --wait >/dev/null 2>&1 || true"   # let first-boot cloud-init release the pkg lock
  vrun "if command -v apt-get >/dev/null; then export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get -y -qq upgrade; elif command -v dnf >/dev/null; then dnf clean all -q 2>/dev/null; dnf -y -q upgrade || true; fi" 2>&1 | tail -2
  vrun "rm -f /etc/sudoers.d/90-cloud-init-users; echo \"$CIUSER ALL=(ALL) ALL\" > /etc/sudoers.d/50-$CIUSER; chmod 0440 /etc/sudoers.d/50-$CIUSER; visudo -cf /etc/sudoers.d/50-$CIUSER"
  vrun "systemctl reboot" || true; sleep 8; waitssh
}

kernel(){
  say "2 KSPP KERNEL BUILD (delivered recipe, ~40min)"
  vscp docs/reference/kernel-build/$OS.sh /tmp/k.sh >/dev/null
  vrun "bash /tmp/k.sh" 2>&1 | grep -iE '==>|Error|DONE|nf_tables|randstruct' | tail -20
  vrun "systemctl reboot" || true; sleep 8; waitssh
  vssh "echo now running: \$(uname -r)"
}

partition(){
  say "3 LVM PARTITIONS (delivered recipe)"
  vscp docs/reference/partition-build/$OS.sh /tmp/p.sh >/dev/null
  vrun "bash /tmp/p.sh" 2>&1 | grep -iE '==>|migrated|FATAL|fstab|relabel' | tail -20
  vrun "systemctl reboot" || true; sleep 8; waitssh
  vrun "mount | grep -c vghard; apt-get check 2>&1 | tail -1"
}

harden(){
  say "4 HARDEN + SCAN + LYNIS (via harness)"
  # install a recent lynis so the harness step 6 can measure (operator-side tool, not hardening)
  vrun "test -x /opt/lynis/lynis || { cd /opt && curl -sSL https://github.com/CISOfy/lynis/archive/refs/tags/3.1.4.tar.gz -o /tmp/l.tgz && tar -xzf /tmp/l.tgz -C /opt && mv /opt/lynis-3.1.4 /opt/lynis; }; echo lynis \$(cd /opt/lynis && ./lynis show version 2>/dev/null)"
  PAVOIS_SUDO_PASSWORD="$PAVOIS_SUDO_PASSWORD" tools/harden_validate.sh "$OS" "$TARGET" "$KEY" "$CIUSER"
}

case "$STAGE" in
  provision) provision;;
  kernel) kernel;;
  partition) partition;;
  harden) harden;;
  all) provision; kernel; partition; harden;;
  *) echo "unknown stage $STAGE"; exit 1;;
esac
say "CLEAN-ROOM STAGE '$STAGE' DONE"
