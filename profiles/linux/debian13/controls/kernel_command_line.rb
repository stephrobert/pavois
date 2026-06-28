# Rendered from pavois reference (pavois-content/debian13.yml). Do not edit by hand.

control 'cmdline-audit' do
  impact 0.3
  title 'Enable Auditing for Processes Which Start Prior to the Audit Daemon'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '6.3.1.2'
  tag('pci-dss' => '10.7.2')
  tag nist: ['3.3.1', 'AC-17(1)', 'AU-10', 'AU-14(1)', 'CM-6(a)', 'IR-5(1)']
  tag level_cis: '2'
  tag ssg: 'grub2_audit_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )audit=1( |$)/) }
  end
  describe command("grep -hwsF 'audit=1' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-audit-backlog-limit' do
  impact 0.3
  title 'Extend Audit Backlog Limit for the Audit Daemon'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '6.3.1.3'
  tag('pci-dss' => '10.7.2')
  tag nist: 'CM-6(a)'
  tag level_cis: '2'
  tag ssg: 'grub2_audit_backlog_limit_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )audit_backlog_limit=8192( |$)/) }
  end
  describe command("grep -hwsF 'audit_backlog_limit=8192' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-iommu-force' do
  impact 0.5
  title 'IOMMU configuration directive'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R7'
  tag level_bp28: 'enhanced'
  tag ssg: 'grub2_enable_iommu_force'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )iommu=force( |$)/) }
  end
  describe command("grep -hwsF 'iommu=force' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-l1tf' do
  impact 0.7
  title 'Configure L1 Terminal Fault mitigations'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_l1tf_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )l1tf=full,force( |$)/) }
  end
  describe command("grep -hwsF 'l1tf=full,force' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-mce' do
  impact 0.5
  title 'Force kernel panic on uncorrected MCEs'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_mce_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )mce=0( |$)/) }
  end
  describe command("grep -hwsF 'mce=0' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-mds' do
  impact 0.5
  title 'Configure Microarchitectural Data Sampling mitigation'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_mds_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )mds=full,nosmt( |$)/) }
  end
  describe command("grep -hwsF 'mds=full,nosmt' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-page-alloc-shuffle' do
  impact 0.5
  title 'Enable randomization of the page allocator'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_page_alloc_shuffle_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )page_alloc\.shuffle=1( |$)/) }
  end
  describe command("grep -hwsF 'page_alloc\.shuffle=1' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-page-poison' do
  impact 0.5
  title 'Enable page allocator poisoning'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag nist: 'CM-6(a)'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_page_poison_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )page_poison=1( |$)/) }
  end
  describe command("grep -hwsF 'page_poison=1' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-pti' do
  impact 0.3
  title 'Enable Kernel Page-Table Isolation (KPTI)'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag nist: 'SI-16'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_pti_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )pti=on( |$)/) }
  end
  describe command("grep -hwsF 'pti=on' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-rng-core-default-quality' do
  impact 0.3
  title 'Configure the confidence in TPM for entropy'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_rng_core_default_quality_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )rng_core\.default_quality=500( |$)/) }
  end
  describe command("grep -hwsF 'rng_core\.default_quality=500' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-slab-nomerge' do
  impact 0.5
  title 'Disable merging of slabs with similar size'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_slab_nomerge_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )slab_nomerge( |$)/) }
  end
  describe command("grep -hwsF 'slab_nomerge' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-slub-debug' do
  impact 0.5
  title 'Enable SLUB/SLAB allocator poisoning'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag nist: 'CM-6(a)'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_slub_debug_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )slub_debug=P( |$)/) }
  end
  describe command("grep -hwsF 'slub_debug=P' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-spec-store-bypass-disable' do
  impact 0.5
  title 'Configure Speculative Store Bypass Mitigation'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_spec_store_bypass_disable_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )spec_store_bypass_disable=on( |$)/) }
  end
  describe command("grep -hwsF 'spec_store_bypass_disable=on' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'cmdline-spectre-v2' do
  impact 0.7
  title 'Enforce Spectre v2 mitigation'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R8'
  tag level_bp28: 'intermediary'
  tag ssg: 'grub2_spectre_v2_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )spectre_v2=on( |$)/) }
  end
  describe command("grep -hwsF 'spectre_v2=on' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end
