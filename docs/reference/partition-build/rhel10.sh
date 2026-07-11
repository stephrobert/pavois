#!/bin/bash
# Pavois — carve separate LVM/XFS partitions on a SECOND disk for the CIS mount/partition
# controls (/home /var /var/log /var/log/audit /var/tmp /opt /srv) on RHEL 10 / AlmaLinux /
# Rocky. DATA, not engine code: like docs/reference/kernel-build/<os>.sh, harden.go delivers
# this verbatim to /usr/local/sbin/pavois-harden-partition.sh for the operator to review and
# run (heavy, reboots). The partition-* / mount-* controls pass once the separate mounts exist.
#
# Attach a >=20G second disk first (Proxmox: qm set <vmid> --scsi1 <storage>:20). The ORIGINAL
# data stays on the root fs (shadowed by each mount), so a failed run is fully recoverable by
# restoring /etc/fstab.pavois-bak and rebooting. Run as root.
#
# RHEL specifics vs the Debian recipe: XFS (not ext4), and SELinux — after migrating data the
# new filesystems carry the wrong contexts, so we schedule a full autorelabel on the next boot
# (/.autorelabel); without it, sshd/systemd/etc. can be denied and the box may not come back.
set -euo pipefail

# rsync drives the migration; ensure it (removed again at the end so no rsync daemon lingers).
command -v rsync >/dev/null 2>&1 || dnf install -y -q rsync >/dev/null 2>&1 || true

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
for lv in home var varlog varlogaudit vartmp opt srv; do mkfs.xfs -f -q "/dev/vghard/$lv"; done

# --- migrate data with strict rsync + integrity assert --------------------------------
mkdir -p /mnt/stage
migrate() { # <lv> <src> [assert_relpath]
  local lv="$1" src="$2" assert="${3:-}"
  mkdir -p "$src"
  mount "/dev/vghard/$lv" /mnt/stage
  local rc=0
  rsync -aHAX --numeric-ids "$src"/ /mnt/stage/ || rc=$?
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
migrate var         /var           lib/rpm            # rpmdb must survive, else dnf is dead
migrate varlog      /var/log
migrate varlogaudit /var/log/audit
migrate vartmp      /var/tmp
migrate opt         /opt
migrate srv         /srv
rmdir /mnt/stage 2>/dev/null || true

# --- fstab (parent before child; /var without noexec — it breaks dnf/rpm scriptlets) --
[ -f /etc/fstab.pavois-bak ] || cp /etc/fstab /etc/fstab.pavois-bak
add() { local lv="$1" mnt="$2" opts="$3"; mkdir -p "$mnt"; sed -i "\| $mnt |d" /etc/fstab
  echo "/dev/vghard/$lv $mnt xfs defaults,$opts 0 0" >> /etc/fstab; }
add home        /home           nodev,nosuid,noexec
add var         /var            nodev,nosuid
add varlog      /var/log        nodev,nosuid,noexec
add varlogaudit /var/log/audit  nodev,nosuid,noexec
add vartmp      /var/tmp        nodev,nosuid,noexec
add opt         /opt            nodev,nosuid           # /opt holds executables (e.g. /opt/cinc); no noexec
add srv         /srv            nodev,nosuid,noexec
echo "==> fstab:"; grep vghard /etc/fstab
systemctl daemon-reload
# migration done: remove rsync so no rsync daemon/service lingers on the hardened host
dnf remove -y -q rsync >/dev/null 2>&1 || true
# SELinux: the freshly-migrated filesystems carry wrong contexts — force a full relabel on the
# reboot that activates the new mounts, or confined services get denied and the host may hang.
touch /.autorelabel
echo "==> DONE — reboot to activate the separate partitions (a one-time SELinux autorelabel runs)."
