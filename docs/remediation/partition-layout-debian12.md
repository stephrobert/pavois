# Recipe: CIS partition layout for the `Mounts` controls (debian12)

The `Mounts` domain has two kinds of control that **cannot be satisfied at runtime by `harden apply`**
on a single-partition install:

- `partition-<mp>` — a mount point must be a **separate filesystem**.
- `mount-<mp>-{nodev,nosuid,noexec}` — that separate filesystem must carry the hardening option.

A stock cloud image has everything on `/`, so these fail. The remediation is **provisioning**: give
the host the CIS partition layout. Verified on a Proxmox Debian 12 VM: **31 / 36 `Mounts` controls
pass** with the scheme below; the remaining 5 are install-time or impractical (see the end).

## What `harden apply` does cover (tmpfs, no partitioning)

`harden apply` creates the tmpfs mounts and options directly, no disk work needed:

- `/tmp`, `/var/tmp` → tmpfs `nodev,nosuid,noexec` (`partition-tmp`, `mount-tmp-*`, `mount-var-tmp-*`)
- `/dev/shm` → `nodev,nosuid,noexec` (`mount-dev-shm-*`)

## Separate filesystems (provisioning)

For `/home`, `/opt`, `/srv`, `/var`, `/var/log`, `/var/log/audit`, add real filesystems with the
options. On Proxmox: attach a second disk and carve them with LVM (safe to migrate on a fresh host),
or partition them at install time. Options per mount point (what the controls check):

| Mount point | Options |
|---|---|
| `/home` | `nodev,nosuid,noexec` |
| `/opt`, `/srv` | `nodev,nosuid` |
| `/var` | `nodev,nosuid` (**not** `noexec`, see below) |
| `/var/log`, `/var/log/audit`, `/var/tmp` | `nodev,nosuid,noexec` |

Runtime carve with a dedicated disk (`/dev/sdb`), migrating the current content:

```bash
# debian12 cloud images ship without LVM/rsync — install them first, or pvcreate/lvcreate
# fail with "command not found" and the carve aborts.
apt-get install -y lvm2 rsync
pvcreate /dev/sdb && vgcreate vgpav /dev/sdb
# LV : mount : options : size   (mount /var before /var/log before /var/log/audit)
for spec in \
  var:/var:nodev,nosuid:4G home:/home:nodev,nosuid,noexec:1G \
  opt:/opt:nodev,nosuid:512M srv:/srv:nodev,nosuid:512M \
  varlog:/var/log:nodev,nosuid,noexec:2G varlogaudit:/var/log/audit:nodev,nosuid,noexec:1G \
  vartmp:/var/tmp:nodev,nosuid,noexec:1G ; do
  IFS=: read lv mp opt sz <<<"$spec"
  lvcreate -y -L "$sz" -n "$lv" vgpav && mkfs.ext4 -qF "/dev/vgpav/$lv"
  mkdir -p "$mp"; mount "/dev/vgpav/$lv" /mnt && rsync -aXS "$mp/" /mnt/ && umount /mnt
  echo "/dev/vgpav/$lv $mp ext4 defaults,$opt 0 2" >> /etc/fstab
done
reboot   # systemd mounts them in depth order from fstab
```

## Install-time only (`/boot`, `/usr`)

`/boot` and `/usr` live on the root disk and are in use at boot, so they must be separated at
**install time** (a `partman` recipe / preseed), not migrated live. This covers `partition-boot`,
`partition-usr`, `mount-boot-noexec`, `mount-boot-nosuid`. A separate `/usr` is also contentious
under systemd usr-merge; treat it as optional.

## Known caveat: `mount-var-noexec`

`noexec` on `/var` **breaks `dpkg`/`apt`** (maintainer scripts execute under `/var`), so it is left
off here and CIS itself recommends only `nodev,nosuid` for `/var`. `mount-var-noexec` is therefore an
over-reach; it should be dropped or marked N/A in the reference rather than "fixed".
