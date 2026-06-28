# Rendered from pavois reference (pavois-content/rhel8.yml). Do not edit by hand.

control 'kconfig-acpi-custom-method' do
  impact 0.3
  title 'Do not allow ACPI methods to be inserted/replaced at run time'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_acpi_custom_method'
  describe command("grep -h '^CONFIG_ACPI_CUSTOM_METHOD=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_ACPI_CUSTOM_METHOD='") do
    its('stdout') { should_not match(/^CONFIG_ACPI_CUSTOM_METHOD=y$/) }
  end
end

control 'kconfig-arm64-sw-ttbr0-pan' do
  impact 0.5
  title 'Emulate Privileged Access Never (PAN)'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R27'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_arm64_sw_ttbr0_pan'
  describe command("grep -h '^CONFIG_ARM64_SW_TTBR0_PAN=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_ARM64_SW_TTBR0_PAN='") do
    its('stdout') { should match(/^CONFIG_ARM64_SW_TTBR0_PAN=y$/) }
  end
end

control 'kconfig-binfmt-misc' do
  impact 0.5
  title 'Disable kernel support for MISC binaries'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R23'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_binfmt_misc'
  describe command("grep -h '^CONFIG_BINFMT_MISC=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_BINFMT_MISC='") do
    its('stdout') { should_not match(/^CONFIG_BINFMT_MISC=y$/) }
  end
end

control 'kconfig-bug' do
  impact 0.5
  title 'Enable support for BUG()'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R19'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_bug'
  describe command("grep -h '^CONFIG_BUG=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_BUG='") do
    its('stdout') { should match(/^CONFIG_BUG=y$/) }
  end
end

control 'kconfig-bug-on-data-corruption' do
  impact 0.3
  title 'Trigger a kernel BUG when data corruption is detected'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R16'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_bug_on_data_corruption'
  describe command("grep -h '^CONFIG_BUG_ON_DATA_CORRUPTION=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_BUG_ON_DATA_CORRUPTION='") do
    its('stdout') { should match(/^CONFIG_BUG_ON_DATA_CORRUPTION=y$/) }
  end
end

control 'kconfig-compat-brk' do
  impact 0.5
  title 'Disable compatibility with brk()'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R17'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_compat_brk'
  describe command("grep -h '^CONFIG_COMPAT_BRK=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_COMPAT_BRK='") do
    its('stdout') { should_not match(/^CONFIG_COMPAT_BRK=y$/) }
  end
end

control 'kconfig-compat-vdso' do
  impact 0.3
  title 'Disable the 32-bit vDSO'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_compat_vdso'
  describe command("grep -h '^CONFIG_COMPAT_VDSO=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_COMPAT_VDSO='") do
    its('stdout') { should_not match(/^CONFIG_COMPAT_VDSO=y$/) }
  end
end

control 'kconfig-debug-credentials' do
  impact 0.3
  title 'Enable checks on credential management'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R16'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_debug_credentials'
  describe command("grep -h '^CONFIG_DEBUG_CREDENTIALS=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_DEBUG_CREDENTIALS='") do
    its('stdout') { should match(/^CONFIG_DEBUG_CREDENTIALS=y$/) }
  end
end

control 'kconfig-debug-fs' do
  impact 0.3
  title 'Disable kernel debugfs'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_debug_fs'
  describe command("grep -h '^CONFIG_DEBUG_FS=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_DEBUG_FS='") do
    its('stdout') { should_not match(/^CONFIG_DEBUG_FS=y$/) }
  end
end

control 'kconfig-debug-list' do
  impact 0.3
  title 'Enable checks on linked list manipulation'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R16'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_debug_list'
  describe command("grep -h '^CONFIG_DEBUG_LIST=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_DEBUG_LIST='") do
    its('stdout') { should match(/^CONFIG_DEBUG_LIST=y$/) }
  end
end

control 'kconfig-debug-notifiers' do
  impact 0.3
  title 'Enable checks on notifier call chains'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R16'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_debug_notifiers'
  describe command("grep -h '^CONFIG_DEBUG_NOTIFIERS=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_DEBUG_NOTIFIERS='") do
    its('stdout') { should match(/^CONFIG_DEBUG_NOTIFIERS=y$/) }
  end
end

control 'kconfig-debug-sg' do
  impact 0.3
  title 'Enable checks on scatter-gather (SG) table operations'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R16'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_debug_sg'
  describe command("grep -h '^CONFIG_DEBUG_SG=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_DEBUG_SG='") do
    its('stdout') { should match(/^CONFIG_DEBUG_SG=y$/) }
  end
end

control 'kconfig-debug-wx' do
  impact 0.5
  title 'Warn on W+X mappings found at boot'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_debug_wx'
  describe command("grep -h '^CONFIG_DEBUG_WX=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_DEBUG_WX='") do
    its('stdout') { should match(/^CONFIG_DEBUG_WX=y$/) }
  end
end

control 'kconfig-devkmem' do
  impact 0.3
  title 'Disable /dev/kmem virtual device support'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_devkmem'
  describe command("grep -h '^CONFIG_DEVKMEM=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_DEVKMEM='") do
    its('stdout') { should_not match(/^CONFIG_DEVKMEM=y$/) }
  end
end

control 'kconfig-fortify-source' do
  impact 0.5
  title 'Harden common str/mem functions against buffer overflows'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_fortify_source'
  describe command("grep -h '^CONFIG_FORTIFY_SOURCE=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_FORTIFY_SOURCE='") do
    its('stdout') { should match(/^CONFIG_FORTIFY_SOURCE=y$/) }
  end
end

control 'kconfig-gcc-plugin-latent-entropy' do
  impact 0.5
  title 'Generate some entropy during boot and runtime'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R21'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_gcc_plugin_latent_entropy'
  describe command("grep -h '^CONFIG_GCC_PLUGIN_LATENT_ENTROPY=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_GCC_PLUGIN_LATENT_ENTROPY='") do
    its('stdout') { should match(/^CONFIG_GCC_PLUGIN_LATENT_ENTROPY=y$/) }
  end
end

control 'kconfig-gcc-plugin-structleak' do
  impact 0.5
  title 'Force initialization of variables containing userspace addresses'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R21'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_gcc_plugin_structleak'
  describe command("grep -h '^CONFIG_GCC_PLUGIN_STRUCTLEAK=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_GCC_PLUGIN_STRUCTLEAK='") do
    its('stdout') { should match(/^CONFIG_GCC_PLUGIN_STRUCTLEAK=y$/) }
  end
end

control 'kconfig-hardened-usercopy' do
  impact 0.7
  title 'Harden memory copies between kernel and userspace'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_hardened_usercopy'
  describe command("grep -h '^CONFIG_HARDENED_USERCOPY=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_HARDENED_USERCOPY='") do
    its('stdout') { should match(/^CONFIG_HARDENED_USERCOPY=y$/) }
  end
end

control 'kconfig-hardened-usercopy-fallback' do
  impact 0.7
  title 'Do not allow usercopy whitelist violations to fallback to object size'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_hardened_usercopy_fallback'
  describe command("grep -h '^CONFIG_HARDENED_USERCOPY_FALLBACK=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_HARDENED_USERCOPY_FALLBACK='") do
    its('stdout') { should_not match(/^CONFIG_HARDENED_USERCOPY_FALLBACK=y$/) }
  end
end

control 'kconfig-hibernation' do
  impact 0.5
  title 'Disable hibernation'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R23'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_hibernation'
  describe command("grep -h '^CONFIG_HIBERNATION=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_HIBERNATION='") do
    its('stdout') { should_not match(/^CONFIG_HIBERNATION=y$/) }
  end
end

control 'kconfig-ia32-emulation' do
  impact 0.5
  title 'Disable IA32 emulation'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R25'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_ia32_emulation'
  describe command("grep -h '^CONFIG_IA32_EMULATION=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_IA32_EMULATION='") do
    its('stdout') { should_not match(/^CONFIG_IA32_EMULATION=y$/) }
  end
end

control 'kconfig-kexec' do
  impact 0.3
  title 'Disable kexec system call'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R23'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_kexec'
  describe command("grep -h '^CONFIG_KEXEC=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_KEXEC='") do
    its('stdout') { should_not match(/^CONFIG_KEXEC=y$/) }
  end
end

control 'kconfig-legacy-ptys' do
  impact 0.5
  title 'Disable legacy (BSD) PTY support'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R23'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_legacy_ptys'
  describe command("grep -h '^CONFIG_LEGACY_PTYS=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_LEGACY_PTYS='") do
    its('stdout') { should_not match(/^CONFIG_LEGACY_PTYS=y$/) }
  end
end

control 'kconfig-legacy-vsyscall-emulate' do
  impact 0.5
  title 'Disable vsyscall emulation'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_legacy_vsyscall_emulate'
  describe command("grep -h '^CONFIG_LEGACY_VSYSCALL_EMULATE=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_LEGACY_VSYSCALL_EMULATE='") do
    its('stdout') { should_not match(/^CONFIG_LEGACY_VSYSCALL_EMULATE=y$/) }
  end
end

control 'kconfig-legacy-vsyscall-none' do
  impact 0.5
  title 'Disable vsyscall mapping'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_legacy_vsyscall_none'
  describe command("grep -h '^CONFIG_LEGACY_VSYSCALL_NONE=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_LEGACY_VSYSCALL_NONE='") do
    its('stdout') { should match(/^CONFIG_LEGACY_VSYSCALL_NONE=y$/) }
  end
end

control 'kconfig-modify-ldt-syscall' do
  impact 0.5
  title 'Disable the LDT (local descriptor table)'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R25'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_modify_ldt_syscall'
  describe command("grep -h '^CONFIG_MODIFY_LDT_SYSCALL=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_MODIFY_LDT_SYSCALL='") do
    its('stdout') { should_not match(/^CONFIG_MODIFY_LDT_SYSCALL=y$/) }
  end
end

control 'kconfig-module-sig' do
  impact 0.5
  title 'Enable module signature verification'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R18'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_module_sig'
  describe command("grep -h '^CONFIG_MODULE_SIG=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_MODULE_SIG='") do
    its('stdout') { should match(/^CONFIG_MODULE_SIG=y$/) }
  end
end

control 'kconfig-module-sig-all' do
  impact 0.5
  title 'Enable automatic signing of all modules'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R18'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_module_sig_all'
  describe command("grep -h '^CONFIG_MODULE_SIG_ALL=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_MODULE_SIG_ALL='") do
    its('stdout') { should match(/^CONFIG_MODULE_SIG_ALL=y$/) }
  end
end

control 'kconfig-module-sig-force' do
  impact 0.5
  title 'Require modules to be validly signed'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R18'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_module_sig_force'
  describe command("grep -h '^CONFIG_MODULE_SIG_FORCE=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_MODULE_SIG_FORCE='") do
    its('stdout') { should match(/^CONFIG_MODULE_SIG_FORCE=y$/) }
  end
end

control 'kconfig-module-sig-sha512' do
  impact 0.5
  title 'Sign kernel modules with SHA-512'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R18'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_module_sig_sha512'
  describe command("grep -h '^CONFIG_MODULE_SIG_SHA512=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_MODULE_SIG_SHA512='") do
    its('stdout') { should match(/^CONFIG_MODULE_SIG_SHA512=y$/) }
  end
end

control 'kconfig-page-poisoning' do
  impact 0.5
  title 'Enable poison of pages after freeing'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R17'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_page_poisoning'
  describe command("grep -h '^CONFIG_PAGE_POISONING=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_PAGE_POISONING='") do
    its('stdout') { should match(/^CONFIG_PAGE_POISONING=y$/) }
  end
end

control 'kconfig-page-poisoning-no-sanity' do
  impact 0.5
  title 'Enable poison without sanity check'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R17'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_page_poisoning_no_sanity'
  describe command("grep -h '^CONFIG_PAGE_POISONING_NO_SANITY=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_PAGE_POISONING_NO_SANITY='") do
    its('stdout') { should match(/^CONFIG_PAGE_POISONING_NO_SANITY=y$/) }
  end
end

control 'kconfig-page-poisoning-zero' do
  impact 0.5
  title 'Use zero for poisoning instead of debugging value'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R17'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_page_poisoning_zero'
  describe command("grep -h '^CONFIG_PAGE_POISONING_ZERO=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_PAGE_POISONING_ZERO='") do
    its('stdout') { should match(/^CONFIG_PAGE_POISONING_ZERO=y$/) }
  end
end

control 'kconfig-page-table-isolation' do
  impact 0.7
  title 'Remove the kernel mapping in user mode'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R25'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_page_table_isolation'
  describe command("grep -h '^CONFIG_PAGE_TABLE_ISOLATION=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_PAGE_TABLE_ISOLATION='") do
    its('stdout') { should match(/^CONFIG_PAGE_TABLE_ISOLATION=y$/) }
  end
end

control 'kconfig-panic-on-oops' do
  impact 0.5
  title 'Kernel panic oops'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R19'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_panic_on_oops'
  describe command("grep -h '^CONFIG_PANIC_ON_OOPS=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_PANIC_ON_OOPS='") do
    its('stdout') { should match(/^CONFIG_PANIC_ON_OOPS=y$/) }
  end
end

control 'kconfig-proc-kcore' do
  impact 0.3
  title 'Disable support for /proc/kkcore'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_proc_kcore'
  describe command("grep -h '^CONFIG_PROC_KCORE=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_PROC_KCORE='") do
    its('stdout') { should_not match(/^CONFIG_PROC_KCORE=y$/) }
  end
end

control 'kconfig-randomize-base' do
  impact 0.5
  title 'Randomize the address of the kernel image (KASLR)'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R25'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_randomize_base'
  describe command("grep -h '^CONFIG_RANDOMIZE_BASE=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_RANDOMIZE_BASE='") do
    its('stdout') { should match(/^CONFIG_RANDOMIZE_BASE=y$/) }
  end
end

control 'kconfig-randomize-memory' do
  impact 0.5
  title 'Randomize the kernel memory sections'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R25'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_randomize_memory'
  describe command("grep -h '^CONFIG_RANDOMIZE_MEMORY=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_RANDOMIZE_MEMORY='") do
    its('stdout') { should match(/^CONFIG_RANDOMIZE_MEMORY=y$/) }
  end
end

control 'kconfig-refcount-full' do
  impact 0.5
  title 'Perform full reference count validation'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_refcount_full'
  describe command("grep -h '^CONFIG_REFCOUNT_FULL=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_REFCOUNT_FULL='") do
    its('stdout') { should match(/^CONFIG_REFCOUNT_FULL=y$/) }
  end
end

control 'kconfig-retpoline' do
  impact 0.5
  title 'Avoid speculative indirect branches in kernel'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_retpoline'
  describe command("grep -h '^CONFIG_RETPOLINE=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_RETPOLINE='") do
    its('stdout') { should match(/^CONFIG_RETPOLINE=y$/) }
  end
end

control 'kconfig-sched-stack-end-check' do
  impact 0.5
  title 'Detect stack corruption on calls to schedule()'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_sched_stack_end_check'
  describe command("grep -h '^CONFIG_SCHED_STACK_END_CHECK=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SCHED_STACK_END_CHECK='") do
    its('stdout') { should match(/^CONFIG_SCHED_STACK_END_CHECK=y$/) }
  end
end

control 'kconfig-seccomp' do
  impact 0.5
  title 'Enable seccomp to safely compute untrusted bytecode'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R20'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_seccomp'
  describe command("grep -h '^CONFIG_SECCOMP=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SECCOMP='") do
    its('stdout') { should match(/^CONFIG_SECCOMP=y$/) }
  end
end

control 'kconfig-seccomp-filter' do
  impact 0.5
  title 'Enable use of Berkeley Packet Filter with seccomp'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R20'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_seccomp_filter'
  describe command("grep -h '^CONFIG_SECCOMP_FILTER=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SECCOMP_FILTER='") do
    its('stdout') { should match(/^CONFIG_SECCOMP_FILTER=y$/) }
  end
end

control 'kconfig-security' do
  impact 0.5
  title 'Enable different security models'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R20'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_security'
  describe command("grep -h '^CONFIG_SECURITY=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SECURITY='") do
    its('stdout') { should match(/^CONFIG_SECURITY=y$/) }
  end
end

control 'kconfig-security-dmesg-restrict' do
  impact 0.5
  title 'Restrict unprivileged access to the kernel syslog'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_security_dmesg_restrict'
  describe command("grep -h '^CONFIG_SECURITY_DMESG_RESTRICT=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SECURITY_DMESG_RESTRICT='") do
    its('stdout') { should match(/^CONFIG_SECURITY_DMESG_RESTRICT=y$/) }
  end
end

control 'kconfig-security-writable-hooks' do
  impact 0.5
  title 'Disable mutable hooks'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R20'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_security_writable_hooks'
  describe command("grep -h '^CONFIG_SECURITY_WRITABLE_HOOKS=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SECURITY_WRITABLE_HOOKS='") do
    its('stdout') { should_not match(/^CONFIG_SECURITY_WRITABLE_HOOKS=y$/) }
  end
end

control 'kconfig-security-yama' do
  impact 0.5
  title 'Enable Yama support'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R20'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_security_yama'
  describe command("grep -h '^CONFIG_SECURITY_YAMA=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SECURITY_YAMA='") do
    its('stdout') { should match(/^CONFIG_SECURITY_YAMA=y$/) }
  end
end

control 'kconfig-slab-freelist-hardened' do
  impact 0.5
  title 'Harden slab freelist metadata'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R17'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_slab_freelist_hardened'
  describe command("grep -h '^CONFIG_SLAB_FREELIST_HARDENED=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SLAB_FREELIST_HARDENED='") do
    its('stdout') { should match(/^CONFIG_SLAB_FREELIST_HARDENED=y$/) }
  end
end

control 'kconfig-slab-freelist-random' do
  impact 0.5
  title 'Randomize slab freelist'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R17'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_slab_freelist_random'
  describe command("grep -h '^CONFIG_SLAB_FREELIST_RANDOM=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SLAB_FREELIST_RANDOM='") do
    its('stdout') { should match(/^CONFIG_SLAB_FREELIST_RANDOM=y$/) }
  end
end

control 'kconfig-slab-merge-default' do
  impact 0.5
  title 'Disallow merge of slab caches'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R17'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_slab_merge_default'
  describe command("grep -h '^CONFIG_SLAB_MERGE_DEFAULT=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SLAB_MERGE_DEFAULT='") do
    its('stdout') { should_not match(/^CONFIG_SLAB_MERGE_DEFAULT=y$/) }
  end
end

control 'kconfig-slub-debug' do
  impact 0.5
  title 'Enable SLUB debugging support'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R17'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_slub_debug'
  describe command("grep -h '^CONFIG_SLUB_DEBUG=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SLUB_DEBUG='") do
    its('stdout') { should match(/^CONFIG_SLUB_DEBUG=y$/) }
  end
end

control 'kconfig-stackprotector' do
  impact 0.5
  title 'Stack Protector buffer overflow detection'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_stackprotector'
  describe command("grep -h '^CONFIG_STACKPROTECTOR=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_STACKPROTECTOR='") do
    its('stdout') { should match(/^CONFIG_STACKPROTECTOR=y$/) }
  end
end

control 'kconfig-stackprotector-strong' do
  impact 0.5
  title 'Strong Stack Protector'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_stackprotector_strong'
  describe command("grep -h '^CONFIG_STACKPROTECTOR_STRONG=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_STACKPROTECTOR_STRONG='") do
    its('stdout') { should match(/^CONFIG_STACKPROTECTOR_STRONG=y$/) }
  end
end

control 'kconfig-strict-kernel-rwx' do
  impact 0.5
  title 'Make the kernel text and rodata read-only'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_strict_kernel_rwx'
  describe command("grep -h '^CONFIG_STRICT_KERNEL_RWX=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_STRICT_KERNEL_RWX='") do
    its('stdout') { should match(/^CONFIG_STRICT_KERNEL_RWX=y$/) }
  end
end

control 'kconfig-strict-module-rwx' do
  impact 0.5
  title 'Make the module text and rodata read-only'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R18'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_strict_module_rwx'
  describe command("grep -h '^CONFIG_STRICT_MODULE_RWX=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_STRICT_MODULE_RWX='") do
    its('stdout') { should match(/^CONFIG_STRICT_MODULE_RWX=y$/) }
  end
end

control 'kconfig-syn-cookies' do
  impact 0.5
  title 'Enable TCP/IP syncookie support'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R22'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_syn_cookies'
  describe command("grep -h '^CONFIG_SYN_COOKIES=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_SYN_COOKIES='") do
    its('stdout') { should match(/^CONFIG_SYN_COOKIES=y$/) }
  end
end

control 'kconfig-unmap-kernel-at-el0' do
  impact 0.5
  title 'Unmap kernel when running in userspace (aka KAISER)'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R27'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_unmap_kernel_at_el0'
  describe command("grep -h '^CONFIG_UNMAP_KERNEL_AT_EL0=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_UNMAP_KERNEL_AT_EL0='") do
    its('stdout') { should match(/^CONFIG_UNMAP_KERNEL_AT_EL0=y$/) }
  end
end

control 'kconfig-vmap-stack' do
  impact 0.5
  title 'User a virtually-mapped stack'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_vmap_stack'
  describe command("grep -h '^CONFIG_VMAP_STACK=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_VMAP_STACK='") do
    its('stdout') { should match(/^CONFIG_VMAP_STACK=y$/) }
  end
end

control 'kconfig-x86-vsyscall-emulation' do
  impact 0.3
  title 'Disable x86 vsyscall emulation'
  tag domain: 'Kernel build'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R15'
  tag level_bp28: 'high'
  tag ssg: 'kernel_config_x86_vsyscall_emulation'
  describe command("grep -h '^CONFIG_X86_VSYSCALL_EMULATION=' /boot/config-$(uname -r) 2>/dev/null; zcat /proc/config.gz 2>/dev/null | grep '^CONFIG_X86_VSYSCALL_EMULATION='") do
    its('stdout') { should_not match(/^CONFIG_X86_VSYSCALL_EMULATION=y$/) }
  end
end
