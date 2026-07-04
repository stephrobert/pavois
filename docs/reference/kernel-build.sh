#!/bin/sh
# Pavois — build a KSPP-hardened kernel. HEAVY: ~20GB free disk, 30-60min, then reboot.
# Review before running. Run as root on a host with enough resources (NOT auto-run by Pavois).
#
# This is DATA, not engine code: harden.go reads it from docs/reference/kernel-build.sh and
# delivers it verbatim to /usr/local/sbin/pavois-harden-kernel.sh (like docs/reference/audit.rules).
# Edit the KSPP option lists / build steps here — never hardcode them in Go.
set -e
KVER=$(uname -r)
if command -v apt-get >/dev/null 2>&1; then
  echo "==> Debian/Ubuntu: build dependencies"
  apt-get update
  apt-get install -y build-essential fakeroot dpkg-dev libncurses-dev bison flex libssl-dev libelf-dev bc dwarves rsync kmod cpio lz4 zstd lzop xz-utils
  GCCV=$(gcc -dumpversion | cut -d. -f1)
  apt-get install -y "gcc-${GCCV}-plugin-dev" || apt-get install -y gcc-plugin-dev || true
  echo "==> kernel source matching the RUNNING kernel (needs deb-src enabled)"
  cd /usr/src
  SRCVER=$(dpkg-query -W -f='${source:Version}' "linux-image-$KVER" 2>/dev/null || true)
  CODENAME=$(. /etc/os-release 2>/dev/null; echo "$VERSION_CODENAME")
  # pin to the running kernel's source version, else this release's current point release, else latest
  apt-get source "linux=$SRCVER" 2>/dev/null || apt-get source "linux/$CODENAME" 2>/dev/null || apt-get source linux
  SRC=$(find /usr/src -maxdepth 1 -type d -name 'linux-*' | sort | tail -1)
  cd "$SRC"
  cp "/boot/config-$KVER" .config
  echo "==> applying Pavois KSPP options"
  for o in DEBUG_CREDENTIALS DEBUG_NOTIFIERS DEBUG_SG PAGE_POISONING PAGE_POISONING_NO_SANITY PAGE_POISONING_ZERO PANIC_ON_OOPS MODULE_SIG MODULE_SIG_ALL MODULE_SIG_FORCE MODULE_SIG_SHA512 GCC_PLUGINS GCC_PLUGIN_LATENT_ENTROPY GCC_PLUGIN_RANDSTRUCT GCC_PLUGIN_STACKLEAK GCC_PLUGIN_STRUCTLEAK GCC_PLUGIN_STRUCTLEAK_BYREF_ALL; do
    scripts/config --enable "CONFIG_$o"
  done
  for o in DEBUG_FS HIBERNATION IA32_EMULATION KEXEC MODIFY_LDT_SYSCALL PROC_KCORE SLAB_MERGE_DEFAULT X86_VSYSCALL_EMULATION DEBUG_INFO; do
    scripts/config --disable "CONFIG_$o"
  done
  scripts/config --disable SYSTEM_TRUSTED_KEYS --disable SYSTEM_REVOCATION_KEYS
  make olddefconfig
  echo "==> building (long)"; make -j"$(nproc)" bindeb-pkg
  echo "==> installing"; dpkg -i ../linux-image-*.deb
  update-grub
  echo "==> DONE — reboot into the hardened kernel, then re-scan with Pavois."
elif command -v dnf >/dev/null 2>&1; then
  # RHEL/AlmaLinux build the kernel from the SRPM (rpmbuild), NOT a raw tree, and ship it WITHOUT
  # gcc-plugin support, so the plugins must be enabled and gcc-plugin-devel installed explicitly.
  # KSPP symbols here are ONLY those valid on the el8 4.18 kernel: the STACKLEAK plugin (merged
  # upstream 4.20) and LEGACY_VSYSCALL_XONLY (5.3) do NOT exist and must NOT be added — vsyscall is
  # set to NONE instead. The fragment only APPENDS options (nothing removed), so netfilter/conntrack,
  # which the nftables firewall depends on, is preserved.
  echo "==> RHEL/AlmaLinux: build a KSPP-hardened kernel from the SRPM"
  dnf install -y rpm-build rpmdevtools dnf-plugins-core
  dnf config-manager --set-enabled powertools 2>/dev/null || dnf config-manager --set-enabled crb 2>/dev/null || subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms 2>/dev/null || true
  dnf install -y gcc-plugin-devel
  rpmdev-setuptree
  echo "==> kernel source (needs the matching *-source repo enabled)"
  dnf download --source kernel || { echo "enable the kernel source repo (dnf config-manager --set-enabled <repo>-source) or fetch kernel-*.src.rpm manually"; exit 1; }
  rpm -Uvh kernel-*.src.rpm
  dnf builddep -y ~/rpmbuild/SPECS/kernel.spec
  # distinct NVR so the build never collides with the stock kernel
  sed -ri 's/^# *%define buildid .*/%define buildid .pavois/' ~/rpmbuild/SPECS/kernel.spec
  ARCH=$(uname -m)
  echo "==> appending Pavois KSPP fragment (el8-4.18-valid symbols only)"
  cat >> ~/rpmbuild/SOURCES/kernel-"$ARCH".config <<'FRAG'
CONFIG_GCC_PLUGINS=y
CONFIG_GCC_PLUGIN_RANDSTRUCT=y
CONFIG_GCC_PLUGIN_STRUCTLEAK=y
CONFIG_GCC_PLUGIN_STRUCTLEAK_BYREF_ALL=y
# CONFIG_LEGACY_VSYSCALL_EMULATE is not set
CONFIG_LEGACY_VSYSCALL_NONE=y
FRAG
  cd ~/rpmbuild/SPECS
  echo "==> building (long)"; rpmbuild -bb --without debug --without debuginfo --without kabidupchk --with baseonly --target="$ARCH" kernel.spec
  echo "==> installing"; dnf install -y ~/rpmbuild/RPMS/"$ARCH"/kernel-*pavois*.rpm
  echo "==> DONE — reboot into the -pavois kernel, then re-scan with Pavois."
else
  echo "unsupported: need apt-get (Debian/Ubuntu) or dnf (RHEL/AlmaLinux)"; exit 1
fi
