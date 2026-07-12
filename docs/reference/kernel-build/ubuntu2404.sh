#!/bin/sh
# Pavois — build a KSPP-hardened kernel. HEAVY: ~20GB free disk, 30-60min, then reboot.
# Review before running. Run as root on a host with enough resources (NOT auto-run by Pavois).
#
# This is DATA, not engine code: harden.go reads it from docs/reference/kernel-build.sh and
# delivers it verbatim to /usr/local/sbin/pavois-harden-kernel.sh (like docs/reference/audit.rules).
# Edit the KSPP option lists / build steps here — never hardcode them in Go.
set -e
KVER=$(uname -r)

# --- Pavois KSPP kconfig sets (shared by every OS branch) --------------------------------------
# These MIRROR Pavois's own `kconfig-*` controls in docs/reference/rules.yml (the curated,
# boot-safe KSPP subset — no WERROR/MODULES=n/CFI that would break a GCC distro build), so a
# kernel from this recipe passes every kconfig control. Cross-version by construction: a symbol
# absent from the target kernel is silently ignored (scripts/config on Debian/Ubuntu; the
# existence check on RHEL), so the SAME lists serve 4.18 (el8) through 6.x (el10 / Debian 13 /
# Ubuntu 26). Renamed symbols carry BOTH spellings, only the present one takes:
#   randstruct : GCC_PLUGIN_RANDSTRUCT (<=4.x plugin)  / RANDSTRUCT_FULL (>=5.x native choice)
#   structleak : GCC_PLUGIN_STRUCTLEAK_BYREF_ALL       / INIT_STACK_ALL_ZERO (>=5.x)
#   pti,retpol : PAGE_TABLE_ISOLATION,RETPOLINE        / MITIGATION_* prefix (>=6.x)
# Keep this in sync with the `kconfig-*` controls (option + set:true/false).
KSPP_ENABLE="BUG BUG_ON_DATA_CORRUPTION DEBUG_CREDENTIALS DEBUG_LIST DEBUG_NOTIFIERS DEBUG_SG DEBUG_WX FORTIFY_SOURCE HARDENED_USERCOPY LEGACY_VSYSCALL_NONE PANIC_ON_OOPS PAGE_POISONING PAGE_POISONING_NO_SANITY PAGE_POISONING_ZERO PAGE_TABLE_ISOLATION MITIGATION_PAGE_TABLE_ISOLATION RANDOMIZE_BASE RANDOMIZE_MEMORY RETPOLINE MITIGATION_RETPOLINE SCHED_STACK_END_CHECK SECCOMP SECCOMP_FILTER SECURITY SECURITY_DMESG_RESTRICT SECURITY_YAMA SLAB_FREELIST_HARDENED SLAB_FREELIST_RANDOM SLUB_DEBUG STACKPROTECTOR STACKPROTECTOR_STRONG STRICT_KERNEL_RWX STRICT_MODULE_RWX SYN_COOKIES VMAP_STACK MODULE_SIG MODULE_SIG_ALL MODULE_SIG_FORCE MODULE_SIG_SHA512 GCC_PLUGINS GCC_PLUGIN_LATENT_ENTROPY GCC_PLUGIN_RANDSTRUCT RANDSTRUCT_FULL GCC_PLUGIN_STACKLEAK GCC_PLUGIN_STRUCTLEAK GCC_PLUGIN_STRUCTLEAK_BYREF_ALL INIT_STACK_ALL_ZERO INIT_ON_ALLOC_DEFAULT_ON INIT_ON_FREE_DEFAULT_ON"
KSPP_DISABLE="ACPI_CUSTOM_METHOD BINFMT_MISC COMPAT_BRK COMPAT_VDSO DEVKMEM HARDENED_USERCOPY_FALLBACK HIBERNATION IA32_EMULATION KEXEC LEGACY_PTYS MODIFY_LDT_SYSCALL PROC_KCORE SECURITY_WRITABLE_HOOKS SLAB_MERGE_DEFAULT X86_VSYSCALL_EMULATION DEBUG_INFO"
# The netfilter/nftables firewall stack — MUST stay present and BUILTIN (=y), never a module
# (#187: olddefconfig pruned it once = firewall-less kernel; and MODULE_SIG_FORCE would block an
# unsigned nf_tables.ko). NETFILTER + NF_TABLES_* are BOOL and reject =m.
NF_STACK="NETFILTER NETFILTER_NETLINK NETFILTER_XTABLES NF_CONNTRACK NF_TABLES NF_TABLES_INET NF_TABLES_IPV4 NF_TABLES_IPV6 NFT_CT NFT_COUNTER NFT_LOG NFT_LIMIT NFT_NAT NFT_MASQ NF_NAT IP_NF_IPTABLES IP6_NF_IPTABLES"


# --- ubuntu2404 ---------------------------------------------------------------------
command -v apt-get >/dev/null 2>&1 || { echo "this script is for ubuntu2404 (needs apt-get)"; exit 1; }
  echo "==> Ubuntu: build dependencies"
  apt-get update
  apt-get install -y build-essential fakeroot dpkg-dev debhelper libncurses-dev bison flex libssl-dev libelf-dev bc dwarves rsync kmod cpio lz4 zstd lzop xz-utils wget
  GCCV=$(gcc -dumpversion | cut -d. -f1)
  apt-get install -y "gcc-${GCCV}-plugin-dev" || apt-get install -y gcc-plugin-dev || true
  # Ubuntu's `apt-get source linux` ships the debian.master packaging whose init/build-version
  # helper makes `make bindeb-pkg` fail (mkdebian -> Makefile.package Error 127). Build the MAINLINE
  # stable tarball of the SAME x.y series from kernel.org instead: it boots on this release and
  # packages cleanly with bindeb-pkg. (Debian's source tree is mainline-compatible; only Ubuntu's isn't.)
  KMAJMIN=$(uname -r | grep -oE '^[0-9]+\.[0-9]+')    # e.g. 6.8
  KMAJ=${KMAJMIN%%.*}
  cd /usr/src
  TARBALL="linux-${KMAJMIN}.tar.xz"
  [ -f "$TARBALL" ] || wget -O "$TARBALL" "https://cdn.kernel.org/pub/linux/kernel/v${KMAJ}.x/${TARBALL}"
  rm -rf "linux-${KMAJMIN}"
  tar -xf "$TARBALL"
  SRC="/usr/src/linux-${KMAJMIN}"
  cd "$SRC"
  cp "/boot/config-$KVER" .config
  # mainline lacks Canonical's signing certs referenced by the stock config → clear the trusted /
  # revocation key paths or the build aborts looking for debian/canonical-certs.pem.
  scripts/config --disable SYSTEM_TRUSTED_KEYS --disable SYSTEM_REVOCATION_KEYS
  scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
  scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
  scripts/config --set-str LOCALVERSION "-pavois"     # distinct name so grub/symlinks pick it over -generic
  echo "==> applying Pavois KSPP options (scripts/config ignores symbols this kernel lacks)"
  for o in $KSPP_ENABLE $NF_STACK; do scripts/config --enable "CONFIG_$o"; done
  for o in $KSPP_DISABLE; do scripts/config --disable "CONFIG_$o"; done
  make olddefconfig
  # abort early if the firewall stack got pruned anyway — never ship a firewall-less kernel
  grep -qE '^CONFIG_NF_TABLES=[ym]' .config || { echo "ERROR: CONFIG_NF_TABLES missing after olddefconfig; the built kernel would have no nftables firewall. Aborting." >&2; exit 1; }
  # gcc-plugin instrumentation roughly DOUBLES the memory of each compile job (~1.5G).
  # A full -j nproc on a small VM gets OOM-killed hours into the build (SIGKILL, exit 137),
  # which is a miserable way to learn the box was too small. Cap the jobs on the RAM.
  MEM_GB=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)
  JOBS=$(( MEM_GB * 2 / 3 )); [ "$JOBS" -lt 1 ] && JOBS=1
  [ "$JOBS" -gt "$(nproc)" ] && JOBS=$(nproc)
  echo "==> building (long, -j$JOBS for ${MEM_GB}G of RAM)"; make -j"$JOBS" bindeb-pkg
  echo "==> installing"; dpkg -i ../linux-image-*.deb ../linux-headers-*.deb
  KREL=$(make -s kernelrelease 2>/dev/null)
  # GRUB boots the HIGHEST version, and the distro's own kernel can out-number ours: Debian 13 ships
  # 6.12.95+deb13 while kernel.org's 6.12 tarball is at 6.12.94. The KSPP kernel was built,
  # installed... and never booted, and every kconfig control failed on a kernel we had replaced.
  # So the recipe pins its kernel as the default entry, BY MENU ID (a name match would hit the
  # distro's own 6.12.94+deb13), and it FLATTENS the menu first: `--unrestricted` lands on the menu
  # entries, never on the "Advanced options" submenu, so a pinned entry inside that submenu stops a
  # password-protected GRUB at `Enter username:` and the machine never boots.
  sed -ri "/^GRUB_DISABLE_SUBMENU=/d" /etc/default/grub
  echo "GRUB_DISABLE_SUBMENU=y" >> /etc/default/grub
  update-grub
  if [ -n "$KREL" ]; then
    OUR=$(grep -oE "gnulinux-${KREL}-advanced-[0-9a-f-]+" /boot/grub/grub.cfg | head -1)
    if [ -n "$OUR" ]; then
      sed -ri "/^GRUB_DEFAULT=/d" /etc/default/grub
      echo "GRUB_DEFAULT=\"$OUR\"" >> /etc/default/grub
      update-grub
      echo "==> default boot entry: Linux $KREL (the KSPP kernel)"
    else
      echo "WARNING: no GRUB entry for $KREL — the stock kernel will keep booting" >&2
    fi
  fi
  # ensure the /vmlinuz + /initrd.img top-level symlinks point to the newest kernel (lynis
  # KRNL-5788): purging the stock cloud kernels can leave them dangling/absent. Reproducible,
  # part of the build so an operator never has to relink by hand.
  NEWK=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
  NEWI=$(ls -1 /boot/initrd.img-* 2>/dev/null | sort -V | tail -1)
  [ -n "$NEWK" ] && ln -sf "$NEWK" /vmlinuz
  [ -n "$NEWI" ] && ln -sf "$NEWI" /initrd.img
  # post-install guard: nf_tables must be reachable in the new kernel — builtin (=y, no .ko) OR
  # a present module. Check the installed config, then (module case) that the .ko exists.
  NV=$(make -s kernelrelease 2>/dev/null)
  if grep -qE '^CONFIG_NF_TABLES=y' "/boot/config-$NV" 2>/dev/null; then
    echo "==> nf_tables builtin (=y) in $NV — firewall OK."
  elif find "/lib/modules/$NV" -name 'nf_tables.ko*' 2>/dev/null | grep -q .; then
    echo "==> nf_tables module present in $NV — firewall OK."
  else
    echo "WARNING: nf_tables missing from $NV — nftables/firewalld will fail; do NOT reboot into it as-is." >&2
  fi
  # KSPP sanity: warn if struct-layout randomization silently ended up disabled
  grep -qE '^CONFIG_(RANDSTRUCT_FULL|GCC_PLUGIN_RANDSTRUCT)=y' "/boot/config-$NV" 2>/dev/null || \
    echo "WARNING: randstruct is NONE in $NV (symbol renamed?) — struct layout not randomized." >&2
  # The kernel is built: drop the toolchain so the hardened box ships no compiler
  # (CIS/lynis HRDN-7222 / posture-no-compilers). A re-run reinstalls it at the top.
  echo "==> removing build toolchain (compiler-free hardened host)"
  apt-get purge -y build-essential gcc g++ cpp "gcc-${GCCV}" "g++-${GCCV}" "cpp-${GCCV}" \
    "gcc-${GCCV}-plugin-dev" >/dev/null 2>&1 || true
  apt-get autoremove --purge -y >/dev/null 2>&1 || true
  # drop the ~1.5 GB source tree + tarball + .deb (no longer needed once installed): frees disk
  # and, critically, stops AIDE's integrity init from checksumming tens of thousands of kernel-
  # source files for many minutes on every subsequent hardening run.
  rm -rf "$SRC" "/usr/src/$TARBALL" /usr/src/linux-image-*.deb /usr/src/linux-headers-*.deb 2>/dev/null || true
  echo "==> DONE — reboot into the hardened kernel, then re-scan with Pavois."
