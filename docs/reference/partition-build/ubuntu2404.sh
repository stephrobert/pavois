#!/bin/bash
# Pavois — carve separate LVM/ext4 partitions on a SECOND disk for the CIS mount/partition
# controls (/home /var /var/log /var/log/audit /var/tmp /opt /srv). DATA, not engine code:
# like docs/reference/kernel-build/<os>.sh, harden.go delivers this verbatim to
# /usr/local/sbin/pavois-harden-partition.sh for the operator to review and run (heavy,
# reboots). Pavois never runs it for you; the partition-* / mount-* controls pass once the
# separate mounts exist. Edit the layout/options HERE, never hardcode them in Go.
#
# Attach a >=20G second disk first (Proxmox: qm set <vmid> --scsi1 <storage>:20). The ORIGINAL
# data stays on the root fs (shadowed by each mount), so a failed run is fully recoverable by
# restoring /etc/fstab.pavois-bak and rebooting. Run as root.
# Pavois — carve separate LVM/ext4 partitions on a second disk for the CIS mount controls.
# Migrates data with integrity checks, writes fstab with hardening mount options; a reboot
# then activates them. The ORIGINAL data stays on the root fs (shadowed by the mount), so a
# failed run is fully recoverable by restoring /etc/fstab.pavois-bak and rebooting. Run as root.
set -euo pipefail

# rsync drives the data migration; ensure it is present (purged again at the end so the
# hardened host ships no rsync daemon — CIS service-rsyncd-disabled / pkg-rsync-removed).
command -v rsync >/dev/null 2>&1 || { apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y rsync >/dev/null 2>&1; }

# --- find the new empty disk (no partitions, not the root disk) ------------------------
ROOTDISK=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" | head -1)
NEW=""
for d in $(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}'); do
  [ "$d" = "$ROOTDISK" ] && continue
  if [ -z "$(lsblk -no NAME "/dev/$d" | tail -n +2)" ]; then NEW="/dev/$d"; break; fi
done

# --- LVM (reuse vghard if a previous run created it) ----------------------------------
if ! vgs vghard >/dev/null 2>&1; then
  [ -n "$NEW" ] || { echo "no empty second disk and no vghard VG"; exit 1; }
  echo "==> creating vghard on $NEW"
  pvcreate -ff -y "$NEW"; vgcreate vghard "$NEW"
  lvcreate -y -L 3G -n home vghard; lvcreate -y -L 6G -n var vghard
  lvcreate -y -L 3G -n varlog vghard; lvcreate -y -L 2G -n varlogaudit vghard
  lvcreate -y -L 2G -n vartmp vghard; lvcreate -y -L 1G -n opt vghard
  lvcreate -y -L 1G -n srv vghard
else
  echo "==> reusing existing vghard"
fi
for lv in home var varlog varlogaudit vartmp opt srv; do mkfs.ext4 -q -F "/dev/vghard/$lv"; done

# --- migrate data with strict rsync + integrity assert --------------------------------
# rsync rc 0 = ok, 24 = source files vanished mid-copy (benign on a live /var). Anything
# else aborts BEFORE we touch fstab, so the system keeps booting from the intact root fs.
mkdir -p /mnt/stage
migrate() { # <lv> <src> [assert_relpath]
  local lv="$1" src="$2" assert="${3:-}"
  mkdir -p "$src"                       # src may not exist yet (e.g. /var/log/audit before auditd)
  mount "/dev/vghard/$lv" /mnt/stage
  local rc=0
  rsync -aHAX --numeric-ids "$src"/ /mnt/stage/ || rc=$?
  # rc 23/24 = partial/vanished files on a live source (benign); the /var integrity assert below
  # still catches a grossly incomplete copy. Anything else aborts before we touch fstab.
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 23 ] && [ "$rc" -ne 24 ]; then
    umount /mnt/stage; echo "FATAL: rsync $src failed rc=$rc" >&2; exit 1
  fi
  if [ -n "$assert" ] && [ ! -e "/mnt/stage/$assert" ]; then
    umount /mnt/stage; echo "FATAL: integrity check failed: $src/$assert not on the new LV" >&2; exit 1
  fi
  umount /mnt/stage
  echo "    migrated $src ($(du -sh "$src" 2>/dev/null | cut -f1))"
}
migrate home        /home
migrate var         /var           lib/dpkg/status
migrate varlog      /var/log
migrate varlogaudit /var/log/audit
migrate vartmp      /var/tmp
migrate opt         /opt
migrate srv         /srv
rmdir /mnt/stage 2>/dev/null || true

# --- fstab (parent before child; /var without noexec — it breaks apt) -----------------
[ -f /etc/fstab.pavois-bak ] || cp /etc/fstab /etc/fstab.pavois-bak
add() { local lv="$1" mnt="$2" opts="$3"; mkdir -p "$mnt"; sed -i "\| $mnt |d" /etc/fstab
  echo "/dev/vghard/$lv $mnt ext4 defaults,$opts 0 2" >> /etc/fstab; }
add home        /home           nodev,nosuid,noexec
add var         /var            nodev,nosuid
add varlog      /var/log        nodev,nosuid,noexec
add varlogaudit /var/log/audit  nodev,nosuid,noexec
add vartmp      /var/tmp        nodev,nosuid,noexec
add opt         /opt            nodev,nosuid           # /opt holds executables (e.g. /opt/cinc); no noexec
add srv         /srv            nodev,nosuid,noexec
echo "==> fstab:"; grep vghard /etc/fstab
systemctl daemon-reload
# migration done: purge rsync so no rsync daemon/service symlink lingers on the hardened host
DEBIAN_FRONTEND=noninteractive apt-get purge -y rsync >/dev/null 2>&1 || true
echo "==> DONE — reboot to activate the separate partitions."
