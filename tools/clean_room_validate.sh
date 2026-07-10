#!/usr/bin/env bash
# Pavois — CLEAN-ROOM end-to-end validation: provision a FRESH VM from the Ubuntu cloud
# image, then run the exact operator pipeline with nothing done by hand:
#   1 provision (Proxmox, from cloud image)   2 KSPP kernel build (delivered recipe)
#   3 LVM partitions (delivered recipe)        4 harden apply -> reboot -> scan + lynis
# The grade + lynis it prints are the honest, reproducible pavois result: a fresh box in,
# a hardened box out, no manual interventions. This is the machine behind "the result must
# be produced by pavois".
#
# Env: PAVOIS_SUDO_PASSWORD (sudo pw of the ci user). Usage:
#   tools/clean_room_validate.sh [stage]   stage = all|provision|kernel|partition|harden
set -euo pipefail
STAGE="${1:-all}"
# All infra targets come from the environment so no lab specifics live in the repo. Defaults use
# RFC-5737 documentation addresses; export the real ones for a run, e.g.
#   PVE=root@pve.example CK_IP=203.0.113.62 CK_GW=203.0.113.1 PAVOIS_SUDO_PASSWORD=... \
#     tools/clean_room_validate.sh all
PVE="${PVE:-root@pve.example}"                                  # Proxmox host (ssh target)
VMID="${CK_VMID:-9000}"; IP="${CK_IP:-203.0.113.62}"; GW="${CK_GW:-203.0.113.1}"
OS="${CK_OS:-ubuntu2404}"; CIUSER="${CK_USER:-pavois}"
CLOUDIMG="${CK_CLOUDIMG:-/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img}"
KEY="${CK_KEY:-$HOME/.ssh/id_ed25519}"; TARGET=$CIUSER@$IP
: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD}"
pssh(){ ssh -o StrictHostKeyChecking=no "$PVE" "$@"; }
vssh(){ ssh -tt -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$KEY" "$TARGET" "$@"; }
vrun(){ vssh "echo '$PAVOIS_SUDO_PASSWORD' | sudo -S bash -c '$1'"; }   # run as root on the VM
say(){ printf '\n\033[1;35m######## %s ########\033[0m\n' "$*"; }
waitssh(){ local n=0; until ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i "$KEY" "$TARGET" true 2>/dev/null; do sleep 5; n=$((n+1)); if [ $n -gt 180 ]; then echo "TIMEOUT waiting for $TARGET"; return 1; fi; done; return 0; }

provision(){
  say "1 PROVISION fresh $OS VM $VMID @ $IP (from cloud image)"
  # push my pubkey to Proxmox for cloud-init
  scp -o StrictHostKeyChecking=no "${KEY}.pub" "$PVE:/root/pavois-ck.pub" >/dev/null
  rm -f /tmp/ck-known
  pssh "qm status $VMID >/dev/null 2>&1 && { qm stop $VMID --skiplock >/dev/null 2>&1; sleep 3; qm destroy $VMID --purge --destroy-unreferenced-disks 1; }; true"
  pssh "qm create $VMID --name pavois-$OS-clean --memory 12288 --cores 8 --cpu host \
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
  vrun "if command -v apt-get >/dev/null; then export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get -y -qq upgrade; elif command -v dnf >/dev/null; then dnf -y -q upgrade; fi" 2>&1 | tail -2
  vrun "rm -f /etc/sudoers.d/90-cloud-init-users; echo \"$CIUSER ALL=(ALL) ALL\" > /etc/sudoers.d/50-$CIUSER; chmod 0440 /etc/sudoers.d/50-$CIUSER; visudo -cf /etc/sudoers.d/50-$CIUSER"
  vrun "systemctl reboot" || true; sleep 8; waitssh
}

kernel(){
  say "2 KSPP KERNEL BUILD (delivered recipe, ~40min)"
  scp -o StrictHostKeyChecking=no -i "$KEY" docs/reference/kernel-build/$OS.sh "$TARGET:/tmp/k.sh" >/dev/null
  vrun "bash /tmp/k.sh" 2>&1 | grep -iE '==>|Error|DONE|nf_tables|randstruct' | tail -20
  vrun "systemctl reboot" || true; sleep 8; waitssh
  vssh "echo now running: \$(uname -r)"
}

partition(){
  say "3 LVM PARTITIONS (delivered recipe)"
  scp -o StrictHostKeyChecking=no -i "$KEY" docs/reference/partition-build/$OS.sh "$TARGET:/tmp/p.sh" >/dev/null
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
