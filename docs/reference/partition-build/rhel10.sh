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

# The recipe must bring its OWN tools: a minimal cloud image may ship neither lvm2 nor rsync.
if ! command -v pvcreate >/dev/null 2>&1 || ! command -v rsync >/dev/null 2>&1; then
  echo "==> installing lvm2 + rsync"
  dnf install -y -q lvm2 rsync >/dev/null 2>&1 || true
fi

# rsync drives the migration; ensure it (removed again at the end so no rsync daemon lingers).
command -v rsync >/dev/null 2>&1 || dnf install -y -q rsync >/dev/null 2>&1 || true

# --- find the new empty disk (no partitions, not the root disk) ------------------------
ROOTDISK=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" | head -1)
NEW=""
for d in $(lsblk -dno NAME,TYPE | awk '$2=="disk"{print $1}'); do
  [ "$d" = "$ROOTDISK" ] && continue
  if [ -z "$(lsblk -no NAME "/dev/$d" | tail -n +2)" ]; then NEW="/dev/$d"; break; fi
done

# --- LVM: SIZE THE VOLUMES FROM THE ACTUAL DATA -----------------------------------------
# Fixed sizes are wrong by construction: a host that has been running (or that just built a
# kernel) can hold 3.8G of logs, and a 3G varlog LV then fails the rsync with a cryptic rc=11
# half way through the migration. Measure, add headroom, and refuse EARLY and clearly if the
# second disk cannot hold the data, instead of discovering it mid-move.
need() {  # <path> <min_gb> -> the LV size in GB: max(min, used * 1.6), rounded up
  local used_mb; used_mb=$(du -sm "$1" 2>/dev/null | cut -f1); used_mb=${used_mb:-0}
  local want=$(( (used_mb * 16 / 10 + 1023) / 1024 ))
  [ "$want" -lt "$2" ] && want="$2"
  echo "$want"
}
S_HOME=$(need /home 3); S_VARLOG=$(need /var/log 3); S_AUDIT=$(need /var/log/audit 2)
S_VARTMP=$(need /var/tmp 2); S_OPT=$(need /opt 1); S_SRV=$(need /srv 1)
# /var is measured WITHOUT the subtrees that get their own LV
S_VAR=$(( $(need /var 6) - S_VARLOG - S_AUDIT - S_VARTMP )); [ "$S_VAR" -lt 6 ] && S_VAR=6
TOTAL=$(( S_HOME + S_VAR + S_VARLOG + S_AUDIT + S_VARTMP + S_OPT + S_SRV ))

if ! vgs vghard >/dev/null 2>&1; then
  [ -n "$NEW" ] || { echo "no empty second disk and no vghard VG"; exit 1; }
  DISK_GB=$(( $(blockdev --getsize64 "$NEW") / 1024 / 1024 / 1024 ))
  if [ "$TOTAL" -gt "$DISK_GB" ]; then
    echo "FATAL: this host needs ${TOTAL}G of separate filesystems (/var/log alone is $(du -sh /var/log | cut -f1))" >&2
    echo "       but the second disk is only ${DISK_GB}G. Attach a bigger disk, or rotate the logs first." >&2
    exit 1
  fi
  echo "==> creating vghard on $NEW (${TOTAL}G of ${DISK_GB}G: home=${S_HOME} var=${S_VAR} varlog=${S_VARLOG} audit=${S_AUDIT} vartmp=${S_VARTMP} opt=${S_OPT} srv=${S_SRV})"
  pvcreate -ff -y "$NEW"; vgcreate vghard "$NEW"
  lvcreate -y -L "${S_HOME}G" -n home vghard;        lvcreate -y -L "${S_VAR}G" -n var vghard
  lvcreate -y -L "${S_VARLOG}G" -n varlog vghard;    lvcreate -y -L "${S_AUDIT}G" -n varlogaudit vghard
  lvcreate -y -L "${S_VARTMP}G" -n vartmp vghard;    lvcreate -y -L "${S_OPT}G" -n opt vghard
  lvcreate -y -L "${S_SRV}G" -n srv vghard
else
  echo "==> reusing existing vghard"
  # a previous run may have sized a volume too small for the data that has grown since
  for pair in "home:$S_HOME" "var:$S_VAR" "varlog:$S_VARLOG" "varlogaudit:$S_AUDIT" \
              "vartmp:$S_VARTMP" "opt:$S_OPT" "srv:$S_SRV"; do
    lv=${pair%%:*}; want=${pair##*:}
    cur=$(lvs --noheadings -o lv_size --units g --nosuffix "vghard/$lv" 2>/dev/null | tr -d ' ' | cut -d. -f1)
    [ -n "$cur" ] || continue
    if [ "$cur" -lt "$want" ]; then
      echo "    growing $lv from ${cur}G to ${want}G (the data no longer fits)"
      lvextend -L "${want}G" "/dev/vghard/$lv" >/dev/null 2>&1 || {
        echo "FATAL: cannot grow $lv to ${want}G: the VG is full. Attach a bigger disk." >&2; exit 1; }
    fi
  done
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
  # `-e` follows symlinks, and a RELATIVE symlink resolves against the staging mount, not the
  # future root: on el9+ /var/lib/rpm is `../../usr/lib/sysimage/rpm`, so a perfectly migrated
  # /var failed the assert. A symlink that EXISTS is a migrated symlink: accept it (-L).
  if [ -n "$assert" ] && [ ! -e "/mnt/stage/$assert" ] && [ ! -L "/mnt/stage/$assert" ]; then
    umount /mnt/stage; echo "FATAL: integrity check failed: $src/$assert not on the new LV" >&2; exit 1
  fi
  umount /mnt/stage
  echo "    migrated $src ($(du -sh "$src" 2>/dev/null | cut -f1))"
}
migrate home        /home
migrate var         /var           lib/dnf            # dnf state must survive the move
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
