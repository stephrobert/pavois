# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'kmod-atm-disabled' do
  impact 0.5
  title 'Disable ATM Support'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'kernel_module_atm_disabled'
  describe kernel_module('atm') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-bluetooth-disabled' do
  impact 0.5
  title 'Disable Bluetooth Kernel Module'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: '3.1.16'
  tag ssg: 'kernel_module_bluetooth_disabled'
  describe kernel_module('bluetooth') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-can-disabled' do
  impact 0.5
  title 'Disable CAN Support'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'kernel_module_can_disabled'
  describe kernel_module('can') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-cfg80211-disabled' do
  impact 0.5
  title 'Disable Kernel cfg80211 Module'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'kernel_module_cfg80211_disabled'
  describe kernel_module('cfg80211') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-cramfs-disabled' do
  impact 0.3
  title 'Disable Mounting of cramfs'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.1.1'
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'kernel_module_cramfs_disabled'
  describe kernel_module('cramfs') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-dccp-disabled' do
  impact 0.5
  title 'Disable DCCP Support'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.2.1'
  tag('pci-dss' => '1.4.2')
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'kernel_module_dccp_disabled'
  describe kernel_module('dccp') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-firewire-core-disabled' do
  impact 0.3
  title 'Disable IEEE 1394 (FireWire) Support'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'kernel_module_firewire-core_disabled'
  describe kernel_module('firewire-core') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-freevxfs-disabled' do
  impact 0.3
  title 'Disable Mounting of freevxfs'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.1.2'
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'kernel_module_freevxfs_disabled'
  describe kernel_module('freevxfs') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-hfs-disabled' do
  impact 0.3
  title 'Disable Mounting of hfs'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.1.3'
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'kernel_module_hfs_disabled'
  describe kernel_module('hfs') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-hfsplus-disabled' do
  impact 0.3
  title 'Disable Mounting of hfsplus'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.1.4'
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'kernel_module_hfsplus_disabled'
  describe kernel_module('hfsplus') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-iwlmvm-disabled' do
  impact 0.5
  title 'Disable Kernel iwlmvm Module'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'kernel_module_iwlmvm_disabled'
  describe kernel_module('iwlmvm') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-iwlwifi-disabled' do
  impact 0.5
  title 'Disable Kernel iwlwifi Module'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'kernel_module_iwlwifi_disabled'
  describe kernel_module('iwlwifi') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-jffs2-disabled' do
  impact 0.3
  title 'Disable Mounting of jffs2'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.1.5'
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'kernel_module_jffs2_disabled'
  describe kernel_module('jffs2') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-loading-disabled' do
  impact 0.5
  title 'Disable loading and unloading of kernel modules'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R10'
  tag level_bp28: 'enhanced'
  tag ssg: 'sysctl_kernel_modules_disabled'
  describe kernel_parameter('kernel.modules_disabled') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.modules_disabled[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'kmod-mac80211-disabled' do
  impact 0.5
  title 'Disable Kernel mac80211 Module'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'kernel_module_mac80211_disabled'
  describe kernel_module('mac80211') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-rds-disabled' do
  impact 0.3
  title 'Disable RDS Support'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.2.3'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'kernel_module_rds_disabled'
  describe kernel_module('rds') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-sctp-disabled' do
  impact 0.5
  title 'Disable SCTP Support'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.2.4'
  tag('pci-dss' => '1.4.2')
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'kernel_module_sctp_disabled'
  describe kernel_module('sctp') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-squashfs-disabled' do
  impact 0.3
  title 'Disable Mounting of squashfs'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.1.6'
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'kernel_module_squashfs_disabled'
  describe kernel_module('squashfs') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-tipc-disabled' do
  impact 0.3
  title 'Disable TIPC Support'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.2.2'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'kernel_module_tipc_disabled'
  describe kernel_module('tipc') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-udf-disabled' do
  impact 0.3
  title 'Disable Mounting of udf'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.1.7'
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'kernel_module_udf_disabled'
  describe kernel_module('udf') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end

control 'kmod-usb-storage-disabled' do
  impact 0.5
  title 'Disable Modprobe Loading of USB Storage Driver'
  tag domain: 'Kernel modules'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.1.8'
  tag('pci-dss' => '3.4.2')
  tag nist: ['3.1.21', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'kernel_module_usb-storage_disabled'
  describe kernel_module('usb_storage') do
    it { should_not be_loaded }
    it { should be_disabled }
  end
end
