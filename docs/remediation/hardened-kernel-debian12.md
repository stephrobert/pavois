# Recipe: build a hardened Debian 12 kernel (KSPP) for the `kconfig-*` controls

The `Kernel build` domain (`kconfig-*`) audits **compile-time** kernel options (`CONFIG_*`).
They cannot be flipped at runtime: the only real remediation is to **build and boot a kernel
compiled with the hardened options** (the Kernel Self-Protection Project / KSPP set). This recipe
is reproducible on a throwaway Debian 12 VM (verified on kernel `6.1`, target `6.1.174-pavhardened`).

> This is an **opt-in, build-time** remediation, not part of `harden apply` (which never recompiles
> a kernel). Treat it as a documented procedure for operators who want the `Kernel build` controls
> to pass on a custom kernel.

## Result (verified)

Booting the rebuilt kernel flips **15 of the targeted controls to PASS** (53/63 `kconfig-*` pass in
total). **7 cannot pass on 6.1** because the control checks an option that was removed or renamed
upstream, these are corpus bugs to fix (mark N/A for 6.1+ or update the `CONFIG_` name), not a build
problem:

| Control | Why it can't pass on 6.1 |
|---|---|
| `kconfig-page-poisoning`, `-no-sanity`, `-zero` | `CONFIG_PAGE_POISONING_{NO_SANITY,ZERO}` were **removed in 5.11** (page poisoning rework) |
| `kconfig-gcc-plugin-randstruct` | renamed to **`CONFIG_RANDSTRUCT_FULL`** in 6.1 |
| `kconfig-gcc-plugin-structleak`, `-byref-all` | structleak gcc plugin unavailable / dependency not met with gcc-12 |
| `kconfig-debug-fs` | `CONFIG_DEBUG_FS` cannot be disabled without breaking the kernel/systemd |

## 1. Build dependencies

```bash
sudo apt-get update
sudo apt-get install -y build-essential bc flex bison libssl-dev libelf-dev dwarves \
  gcc-12-plugin-dev linux-source-6.1 fakeroot kmod cpio rsync lz4
```

- **`lz4`** is required: the kernel image is LZ4-compressed; without it the build fails late with
  `lz4: not found`.
- **`gcc-12-plugin-dev`** provides the GCC plugins (`latent_entropy`, `stackleak`).

## 2. Configure (base config + KSPP fragment)

```bash
mkdir -p ~/kbuild && cd ~/kbuild
tar xf /usr/src/linux-source-6.1.tar.*
cd linux-source-6.1
cp /boot/config-"$(uname -r)" .config        # start from the running config
make olddefconfig
yes "" | make localmodconfig                  # optional: only currently-loaded modules -> much faster build
./scripts/kconfig/merge_config.sh -m .config kspp.fragment   # the fragment below
```

`kspp.fragment` (the hardening options the controls expect):

```
CONFIG_DEBUG_CREDENTIALS=y
# CONFIG_DEBUG_FS is not set
CONFIG_DEBUG_NOTIFIERS=y
CONFIG_DEBUG_SG=y
CONFIG_GCC_PLUGIN_LATENT_ENTROPY=y
CONFIG_GCC_PLUGIN_STACKLEAK=y
# CONFIG_HIBERNATION is not set
# CONFIG_IA32_EMULATION is not set
# CONFIG_KEXEC is not set
# CONFIG_MODIFY_LDT_SYSCALL is not set
CONFIG_MODULE_SIG_ALL=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MODULE_SIG_SHA512=y
CONFIG_PANIC_ON_OOPS=y
# CONFIG_PROC_KCORE is not set
# CONFIG_SLAB_MERGE_DEFAULT is not set
# CONFIG_X86_VSYSCALL_EMULATION is not set

# Netfilter — MUST be built-in (=y), never modules. The hardened profile applies
# kernel.modules_disabled=1, so any =m firewall module can never load post-hardening;
# and `make localmodconfig` (step 2) DROPS these entirely if they weren't loaded at
# build time. Without them ufw/nft/iptables fail ("Table filter does not exist" /
# "Protocol not supported") and firewall-default-deny can never pass (Lynis FIRE-4512).
CONFIG_NETFILTER=y
CONFIG_NF_CONNTRACK=y
CONFIG_NF_TABLES=y
CONFIG_NF_TABLES_INET=y
CONFIG_NFT_CT=y
CONFIG_NFT_COMPAT=y
CONFIG_NETFILTER_XTABLES=y
CONFIG_NETFILTER_XT_MATCH_CONNTRACK=y
CONFIG_NETFILTER_XT_MATCH_STATE=y
CONFIG_NETFILTER_XT_TARGET_REJECT=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_IP_NF_TARGET_REJECT=y
CONFIG_IP6_NF_IPTABLES=y
CONFIG_IP6_NF_FILTER=y
CONFIG_IP6_NF_TARGET_REJECT=y
```

Then fix the **Debian signing keys** (the classic rebuild gotcha) and re-sync:

```bash
./scripts/config --set-str SYSTEM_TRUSTED_KEYS ""        # Debian's cert paths don't exist here
./scripts/config --set-str SYSTEM_REVOCATION_KEYS ""
./scripts/config --set-str MODULE_SIG_KEY "certs/signing_key.pem"   # default: auto-generated, do NOT empty it
./scripts/config --disable DEBUG_INFO --enable DEBUG_INFO_NONE      # smaller/faster build
make olddefconfig
```

> **Do not set `MODULE_SIG_KEY` to an empty string.** With `MODULE_SIG_FORCE=y`, an empty key makes
> `sign-file` fail (`SSL error ... DECODER routines::unsupported`). Keep the default
> `certs/signing_key.pem`; the build auto-generates it and signs every module.

## 3. Build + install

```bash
make -j"$(nproc)" bindeb-pkg LOCALVERSION=-pavhardened     # ~20-40 min on 12 cores
sudo dpkg -i ../linux-image-6.1.*-pavhardened_*.deb
sudo update-grub
sudo reboot
```

A VM/build host with **>= 12 cores, >= 12 GB RAM, >= 40 GB disk** builds comfortably.
`MODULE_SIG_FORCE=y` means only modules built here (and signed) will load: if you used
`localmodconfig`, make sure every module the host needs at boot (virtio, filesystem, network, **and
netfilter** — see the fragment) was loaded when you ran it, or the VM may not come back / the
firewall will not work. Snapshot first if your storage supports it.

> **Netfilter is the classic `localmodconfig` casualty.** If the build host had no firewall active,
> `localmodconfig` sets `NF_TABLES`/`IP_NF_FILTER` to `n` and the resulting kernel cannot run ufw,
> nft or iptables at all. The netfilter block in the fragment forces them **built-in** so they
> survive both `localmodconfig` and the hardened profile's `kernel.modules_disabled=1`.

## 4. Verify

```bash
uname -r                                   # -> 6.1.x-pavhardened
pavois scan <target> --sudo --on-target    # the Kernel build domain: 53/63 kconfig-* PASS
```
