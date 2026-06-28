# Rendered from pavois reference (pavois-content/ubuntu2204.yml). Do not edit by hand.

control 'service-apport-disabled' do
  impact 0.5
  title 'Disable Apport Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.5.5'
  tag level_cis: '1'
  tag ssg: 'service_apport_disabled'
  describe service('apport.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-auditd-enabled' do
  impact 0.5
  title 'Enable auditd Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R33'
  tag cis: '6.3.1.2'
  tag('pci-dss' => '10.2.1')
  tag nist: ['3.3.1', 'AC-2(g)', 'AC-6(9)', 'AU-10', 'AU-12(c)', 'AU-14(1)', 'AU-2(d)', 'AU-3', 'CM-6(a)', 'SI-4(23)']
  tag stig: 'UBTU-22-653015'
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

control 'service-cron-enabled' do
  impact 0.5
  title 'Enable cron Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '2.4.1.1'
  tag nist: 'CM-6(a)'
  tag level_cis: '1'
  tag ssg: 'service_cron_enabled'
  describe service('cron.service') do
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

control 'service-dhcpd-disabled' do
  impact 0.5
  title 'Disable DHCP Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.3'
  tag nist: ['CM-7(a)', 'CM-7(b)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'service_dhcpd_disabled'
  describe service('dhcpd.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-dhcpd6-disabled' do
  impact 0.5
  title 'Disable DHCPD6 Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.3'
  tag level_cis: '1'
  tag ssg: 'service_dhcpd6_disabled'
  describe service('dhcpd6.service') do
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

control 'service-dovecot-disabled' do
  impact 0.5
  title 'Disable Dovecot Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.8'
  tag level_cis: '1'
  tag ssg: 'service_dovecot_disabled'
  describe service('dovecot.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-httpd-disabled' do
  impact 0.5
  title 'Disable apache2 Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.18'
  tag nist: ['CM-7(a)', 'CM-7(b)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'service_httpd_disabled'
  describe service('apache2.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-kdump-disabled' do
  impact 0.5
  title 'Disable KDump Kernel Crash Analyzer (kdump)'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag stig: 'UBTU-22-213015'
  tag ssg: 'service_kdump_disabled'
  describe service('kdump-tools.service') do
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

control 'service-nginx-disabled' do
  impact 0.5
  title 'Disable nginx Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.18'
  tag level_cis: '1'
  tag ssg: 'service_nginx_disabled'
  describe service('nginx.service') do
    it { should_not be_enabled }
    it { should_not be_running }
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

control 'service-rsyncd-disabled' do
  impact 0.5
  title 'Ensure rsyncd service is disabled'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.13'
  tag('pci-dss' => '2.2.4')
  tag level_cis: '1'
  tag ssg: 'service_rsyncd_disabled'
  describe service('rsyncd.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-slapd-disabled' do
  impact 0.5
  title 'Disable LDAP Server (slapd)'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.7'
  tag level_cis: '1'
  tag ssg: 'service_slapd_disabled'
  describe service('slapd.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-smb-disabled' do
  impact 0.3
  title 'Disable Samba'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.14'
  tag level_cis: '1'
  tag ssg: 'service_smb_disabled'
  describe service('smbd.service') do
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
  tag cis: '2.1.15'
  tag level_cis: '1'
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
  tag cis: '2.1.17'
  tag level_cis: '1'
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
  tag stig: 'UBTU-22-255015'
  tag ssg: 'service_sshd_enabled'
  describe service('ssh.service') do
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
  tag stig: 'UBTU-22-254015'
  tag level_bp28: 'intermediary'
  tag ssg: 'service_sssd_enabled'
  describe service('sssd.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-systemd-journal-upload-enabled' do
  impact 0.5
  title 'Enable systemd-journal-upload Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '6.2.1.2.3'
  tag level_cis: '1'
  tag ssg: 'service_systemd-journal-upload_enabled'
  describe service('systemd-journal-upload.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-systemd-journald-enabled' do
  impact 0.5
  title 'Enable systemd-journald Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '6.2.1.1.1'
  tag nist: 'SC-24'
  tag level_cis: '1'
  tag ssg: 'service_systemd-journald_enabled'
  describe service('systemd-journald.service') do
    it { should be_enabled }
    it { should be_running }
  end
end

control 'service-tftp-disabled' do
  impact 0.7
  title 'Disable tftpd-hpa Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.16'
  tag nist: ['CM-7(a)', 'CM-7(b)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'service_tftp_disabled'
  describe service('tftpd-hpa.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-vsftpd-disabled' do
  impact 0.5
  title 'Disable vsftpd Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.6'
  tag nist: ['CM-7(a)', 'CM-7(b)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'service_vsftpd_disabled'
  describe service('vsftpd.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-xinetd-disabled' do
  impact 0.5
  title 'Disable xinetd Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.19'
  tag nist: ['CM-7(a)', 'CM-7(b)', 'CM-6(a)', '3.4.7']
  tag level_cis: '1'
  tag ssg: 'service_xinetd_disabled'
  describe service('xinetd.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end

control 'service-ypserv-disabled' do
  impact 0.5
  title 'Disable ypserv Service'
  tag domain: 'systemd services'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '2.1.10'
  tag level_cis: '1'
  tag ssg: 'service_ypserv_disabled'
  describe service('ypserv.service') do
    it { should_not be_enabled }
    it { should_not be_running }
  end
end
