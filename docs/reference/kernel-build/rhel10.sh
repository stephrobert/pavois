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


# --- rhel10 ---------------------------------------------------------------------
command -v dnf >/dev/null 2>&1 || { echo "this script is for rhel10 (needs dnf)"; exit 1; }
  # RHEL/AlmaLinux build the kernel from the SRPM (rpmbuild), NOT a raw tree, and ship it WITHOUT
  # gcc-plugin support, so the plugins must be enabled and gcc-plugin-devel installed explicitly.
  # The shared KSPP set is applied below with a per-symbol existence check against the target
  # kernel's own base config, so el8 (4.18), el9 (5.14) and el10 (6.x) each take only what they
  # support (STACKLEAK is 4.20+, LEGACY_VSYSCALL_* is 5.3+, RANDSTRUCT_FULL is 5.x+ ...). vsyscall
  # is a Kconfig CHOICE the strict process_configs.sh rejects, so it stays on the cmdline.
  echo "==> RHEL/AlmaLinux: build a KSPP-hardened kernel from the SRPM"
  # A pavois-hardened host BREAKS the kernel build: fapolicyd (application allow-listing) denies
  # open() on the untrusted .so build artifacts (e.g. arch/x86/entry/vdso/vdso64.so.dbg ->
  # "vdso2c: Operation not permitted"), and a freshly-mounted build filesystem is SELinux
  # unlabeled_t. Relax BOTH for the build only, and restore them afterwards.
  FAPO_WAS=$(systemctl is-active fapolicyd 2>/dev/null || true); SE_WAS=$(getenforce 2>/dev/null || echo Disabled)
  [ "$FAPO_WAS" = active ] && systemctl stop fapolicyd || true
  [ "$SE_WAS" = Enforcing ] && setenforce 0 || true
  restore_security() { [ "$FAPO_WAS" = active ] && systemctl start fapolicyd || true; [ "$SE_WAS" = Enforcing ] && setenforce 1 || true; }
  trap restore_security EXIT
  # The build must LOAD kernel modules (crypto_user, for the FIPS kcapi hashing step). If a prior
  # hardening set kernel.modules_disabled=1 (the kmod-loading-disabled control, via
  # pavois-modules-disabled.service), module loading is frozen one-way and the build fails with
  # "libkcapi ... cannot open netlink socket". It can only be cleared by a REBOOT with that service
  # disabled — do that BEFORE building on such a host.
  if [ "$(sysctl -n kernel.modules_disabled 2>/dev/null)" = 1 ]; then
    echo "ERROR: kernel.modules_disabled=1 freezes module loading; the kernel build needs crypto_user." >&2
    echo "Run: systemctl disable pavois-modules-disabled.service && reboot, then re-run this build." >&2
    exit 1
  fi
  modprobe crypto_user 2>/dev/null || true
  dnf install -y rpm-build rpmdevtools dnf-plugins-core
  dnf config-manager --set-enabled powertools 2>/dev/null || dnf config-manager --set-enabled crb 2>/dev/null || subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms 2>/dev/null || true
  dnf install -y gcc-plugin-devel
  rpmdev-setuptree
  echo "==> kernel source (needs the matching *-source repo enabled)"
  dnf download --source kernel || { echo "enable the kernel source repo (dnf config-manager --set-enabled <repo>-source) or fetch kernel-*.src.rpm manually"; exit 1; }
  rpm -Uvh kernel-*.src.rpm
  dnf builddep -y ~/rpmbuild/SPECS/kernel.spec
  # distinct NVR so the build never collides with the stock kernel
  sed -ri 's/^#[[:space:]]*%?[[:space:]]*define buildid .*/%define buildid .pavois/' ~/rpmbuild/SPECS/kernel.spec
  # --without debuginfo strips the vmlinux BTF, so the spec's `bpftool btf dump file vmlinux >
  # vmlinux.h` (a kernel-devel BPF-dev header, not needed for a hardened kernel) fails "load BTF
  # ... No such file". Make it non-fatal so packaging continues with an empty vmlinux.h.
  sed -ri 's#(bpftool btf dump file vmlinux format c > .*/vmlinux.h)#\1 || :#' ~/rpmbuild/SPECS/kernel.spec
  ARCH=$(uname -m)
  echo "==> applying Pavois KSPP to the base config (only symbols THIS kernel version has)"
  BASECFG=~/rpmbuild/SOURCES/kernel-"$ARCH".config
  # Edit the base .config directly + a per-symbol existence check, so el8 (4.18), el9 (5.14) and
  # el10 (6.x) each take exactly the KSPP symbols they support — process_configs.sh never sees a
  # name from a newer kernel. Same shared KSPP_ENABLE/KSPP_DISABLE/NF_STACK as the Debian branch.
  setcfg() {  # $1 symbol  $2 y|n — no-op if the symbol is absent from THIS kernel's base config
    grep -qE "^(CONFIG_$1=|# CONFIG_$1 is not set)" "$BASECFG" || return 0
    sed -ri "/^(CONFIG_$1=|# CONFIG_$1 )/d" "$BASECFG"
    if [ "$2" = y ]; then echo "CONFIG_$1=y" >> "$BASECFG"; else echo "# CONFIG_$1 is not set" >> "$BASECFG"; fi
  }
  # vsyscall is a Kconfig CHOICE the RHEL spec's strict process_configs.sh rejects if edited here;
  # leave it to the kernel cmdline (vsyscall=none) instead of the config.
  for o in $KSPP_ENABLE $NF_STACK; do case "$o" in LEGACY_VSYSCALL_*|X86_VSYSCALL_EMULATION) continue;; esac; setcfg "$o" y; done
  for o in $KSPP_DISABLE;         do case "$o" in LEGACY_VSYSCALL_*|X86_VSYSCALL_EMULATION) continue;; esac; setcfg "$o" n; done
  # --without kabichk: GCC_PLUGIN_RANDSTRUCT randomises struct layout and intentionally BREAKS
  # kABI, so the RHEL kABI stability check must be off (a KSPP kernel is not kABI-compatible with
  # the stock one; out-of-tree kmods built against stock symbols will not load — an accepted tradeoff).
  cd ~/rpmbuild/SPECS
  # gcc-plugin instrumentation ~doubles per-compile-job RAM; a full -j nproc can OOM (SIGKILL,
  # exit 137). Cap parallelism to fit memory (~1.5GB/job) via _smp_mflags.
  echo "==> building (long)"; rpmbuild --define "_smp_mflags -j6" -bb --without debug --without debuginfo --without kabidupchk --without kabichk --with baseonly --target="$ARCH" kernel.spec
  echo "==> installing"; dnf install -y ~/rpmbuild/RPMS/"$ARCH"/kernel-*pavois*.rpm
  echo "==> DONE — reboot into the -pavois kernel, then re-scan with Pavois."
