# Rendered from pavois reference (pavois-content/fedora.yml). Do not edit by hand.

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

control 'cmdline-nousb' do
  impact 0.5
  title 'Disable Kernel Support for USB via Bootloader Configuration'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'grub2_nousb_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )kernel=ALL( |$)/) }
  end
  describe command("grep -hwsF 'kernel=ALL' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
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

control 'cmdline-selinux' do
  impact 0.5
  title 'Ensure SELinux Not Disabled in /etc/default/grub'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.3.1.2'
  tag('pci-dss' => '1.2.6')
  tag nist: '3.1.2'
  tag level_cis: '1'
  tag ssg: 'grub2_enable_selinux'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )selinux=0( |$)/) }
  end
  describe command("grep -hwsF 'selinux=0' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
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

control 'cmdline-vsyscall' do
  impact 0.5
  title 'Disable vsyscalls'
  tag domain: 'Kernel command line'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'grub2_vsyscall_argument'
  describe command('cat /proc/cmdline') do
    its('stdout') { should match(/(^| )vsyscall=none( |$)/) }
  end
  describe command("grep -hwsF 'vsyscall=none' /etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end
