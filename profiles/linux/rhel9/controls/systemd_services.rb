# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'service-auditd-enabled' do
  impact 0.5
  title 'Enable auditd Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R33'
  tag cis: '6.3.1.4'
  tag('pci-dss' => '10.2.1')
  tag nist: ['3.3.1', 'AC-2(g)', 'AC-6(9)', 'AU-10', 'AU-12(c)', 'AU-14(1)', 'AU-2(d)', 'AU-3', 'CM-6(a)', 'SI-4(23)']
  tag level_bp28: 'intermediary'
  tag level_cis: '2'
  tag ssg: 'service_auditd_enabled'
  describe service('auditd.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-autofs-disabled' do
  impact 0.5
  title 'Disable the Automounter'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.1'
  tag nist: ['3.4.6', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'service_autofs_disabled'
  describe service('autofs.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-avahi-daemon-disabled' do
  impact 0.5
  title 'Disable Avahi Server Software'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.2'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'service_avahi-daemon_disabled'
  describe service('avahi-daemon.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-bluetooth-disabled' do
  impact 0.5
  title 'Disable Bluetooth Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.1.3'
  tag nist: ['3.1.16', 'AC-18(3)', 'AC-18(a)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'service_bluetooth_disabled'
  describe service('bluetooth.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-crond-enabled' do
  impact 0.5
  title 'Enable cron Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '2.4.1.1'
  tag level_cis: '1'
  tag ssg: 'service_crond_enabled'
  describe service('crond.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-cups-disabled' do
  impact 0.5
  title 'Disable the CUPS Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.11'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'service_cups_disabled'
  describe service('cups.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-debug-shell-disabled' do
  impact 0.5
  title 'Disable debug-shell SystemD Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: '3.4.5'
  tag ssg: 'service_debug-shell_disabled'
  describe service('debug-shell.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-dnsmasq-disabled' do
  impact 0.5
  title 'Disable dnsmasq Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.5'
  tag level_cis: '1'
  tag ssg: 'service_dnsmasq_disabled'
  describe service('dnsmasq.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-fapolicyd-enabled' do
  impact 0.5
  title 'Enable the File Access Policy Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag ssg: 'service_fapolicyd_enabled'
  describe service('fapolicyd.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-kdump-disabled' do
  impact 0.5
  title 'Disable KDump Kernel Crash Analyzer (kdump)'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'service_kdump_disabled'
  describe service('kdump.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-nfs-disabled' do
  impact 0.5
  title 'Disable Network File System (nfs)'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.9'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'service_nfs_disabled'
  describe service('nfs-server.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-pcscd-enabled' do
  impact 0.5
  title 'Enable the pcscd Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag ssg: 'service_pcscd_enabled'
  describe service('pcscd.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-rpcbind-disabled' do
  impact 0.3
  title 'Disable rpcbind Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.12'
  tag('pci-dss' => '2.2.4')
  tag level_cis: '1'
  tag ssg: 'service_rpcbind_disabled'
  describe service('rpcbind.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-snmpd-disabled' do
  impact 0.3
  title 'Disable snmpd Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'service_snmpd_disabled'
  describe service('snmpd.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-squid-disabled' do
  impact 0.5
  title 'Disable Squid'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'service_squid_disabled'
  describe service('squid.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-sshd-enabled' do
  impact 0.5
  title 'Enable the OpenSSH Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag nist: ['3.1.13', 'CM-6(a)', 'SC-8', 'SC-8(1)', 'SC-8(2)', 'SC-8(3)', 'SC-8(4)']
  tag ssg: 'service_sshd_enabled'
  describe service('sshd.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-sssd-enabled' do
  impact 0.5
  title 'Enable the SSSD Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R67'
  tag nist: ['CM-6(a)', 'IA-5(10)']
  tag level_bp28: 'intermediary'
  tag ssg: 'service_sssd_enabled'
  describe service('sssd.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-systemd-coredump-disabled' do
  impact 0.5
  title 'Disable acquiring, saving, and processing core dumps'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'service_systemd-coredump_disabled'
  describe service('systemd-coredump.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-systemd-journald-enabled' do
  impact 0.5
  title 'Enable systemd-journald Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '6.2.1.1'
  tag nist: 'SC-24'
  tag level_cis: '1'
  tag ssg: 'service_systemd-journald_enabled'
  describe service('systemd-journald.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-telnet-disabled' do
  impact 0.7
  title 'Disable telnet Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: '3.1.13'
  tag ssg: 'service_telnet_disabled'
  describe service('telnet.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-usbguard-enabled' do
  impact 0.5
  title 'Enable the USBGuard Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag ssg: 'service_usbguard_enabled'
  describe service('usbguard.service') do
    it { should be_enabled }
    it { should be_running }
  end
end
