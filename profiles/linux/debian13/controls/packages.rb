# Rendered from pavois reference (pavois-content/debian13.yml). Do not edit by hand.

control 'pkg-aide-installed' do
  impact 0.5
  title 'Install AIDE'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R76'
  tag('pci-dss' => '11.5.2')
  tag nist: 'CM-6(a)'
  tag level_bp28: 'intermediary'
  tag ssg: 'package_aide_installed'
  describe package('aide') do
    it { should be_installed }
  end
end

control 'pkg-apparmor-installed' do
  impact 0.5
  title 'Ensure AppArmor is installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R45'
  tag level_bp28: 'enhanced'
  tag ssg: 'package_apparmor_installed'
  describe package('apparmor') do
    it { should be_installed }
  end
end

control 'pkg-audit-installed' do
  impact 0.5
  title 'Ensure the audit Subsystem is Installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R33'
  tag cis: '6.3.1.1'
  tag('pci-dss' => '10.2.1')
  tag nist: ['AC-7(a)', 'AU-12(2)', 'AU-14', 'AU-2(a)', 'AU-7(1)', 'AU-7(2)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '2'
  tag ssg: 'package_audit_installed'
  describe package('auditd') do
    it { should be_installed }
  end
end

control 'pkg-audit-libs-installed' do
  impact 0.5
  title 'Ensure the audit-libs package as a part of audit Subsystem is Installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '6.3.1.1'
  tag level_cis: '2'
  tag ssg: 'package_audit-libs_installed'
  describe package('libaudit1') do
    it { should be_installed }
  end
end

control 'pkg-bind-removed' do
  impact 0.3
  title 'Uninstall bind Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.4'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'package_bind_removed'
  describe package('bind') do
    it { should_not be_installed }
  end
end

control 'pkg-cron-installed' do
  impact 0.5
  title 'Install the cron service'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag('pci-dss' => '2.2.6')
  tag nist: 'CM-6(a)'
  tag ssg: 'package_cron_installed'
  describe package('cron') do
    it { should be_installed }
  end
end

control 'pkg-cyrus-imapd-removed' do
  impact 0.5
  title 'Uninstall cyrus-imapd Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.8'
  tag level_cis: '1'
  tag ssg: 'package_cyrus-imapd_removed'
  describe package('cyrus-imapd') do
    it { should_not be_installed }
  end
end

control 'pkg-dhcp-removed' do
  impact 0.5
  title 'Uninstall DHCP Server Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag ssg: 'package_dhcp_removed'
  describe package('dhcp') do
    it { should_not be_installed }
  end
end

control 'pkg-dovecot-removed' do
  impact 0.5
  title 'Uninstall dovecot Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.8'
  tag level_cis: '1'
  tag ssg: 'package_dovecot_removed'
  describe package('dovecot') do
    it { should_not be_installed }
  end
end

control 'pkg-ftp-removed' do
  impact 0.3
  title 'Remove ftp Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.2.1'
  tag('pci-dss' => '2.2.4')
  tag level_cis: '1'
  tag ssg: 'package_ftp_removed'
  describe package('ftp') do
    it { should_not be_installed }
  end
end

control 'pkg-gdm-removed' do
  impact 0.5
  title 'Remove the GDM Package Group'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '1.8.1'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'package_gdm_removed'
  describe package('gdm') do
    it { should_not be_installed }
  end
end

control 'pkg-httpd-removed' do
  impact 0.5
  title 'Uninstall httpd Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.18'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'package_httpd_removed'
  describe package('httpd') do
    it { should_not be_installed }
  end
end

control 'pkg-inetutils-telnetd-removed' do
  impact 0.7
  title 'Uninstall the inet-based telnet server'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_inetutils-telnetd_removed'
  describe package('inetutils-telnetd') do
    it { should_not be_installed }
  end
end

control 'pkg-kea-removed' do
  impact 0.5
  title 'Uninstall kea Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag level_bp28: 'minimal'
  tag ssg: 'package_kea_removed'
  describe package('kea') do
    it { should_not be_installed }
  end
end

control 'pkg-libpam-apparmor-installed' do
  impact 0.5
  title 'Install the pam_apparmor Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R45'
  tag nist: ['AC-3(4)', 'AC-6(8)', 'AC-6(10)', 'CM-7(5)(b)', 'CM-7(2)', 'SC-7(21)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'package_pam_apparmor_installed'
  describe package('libpam-apparmor') do
    it { should be_installed }
  end
end

control 'pkg-logrotate-installed' do
  impact 0.5
  title 'Ensure logrotate is Installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R71'
  tag('pci-dss' => '10.5.1')
  tag nist: 'CM-6(a)'
  tag level_bp28: 'enhanced'
  tag ssg: 'package_logrotate_installed'
  describe package('logrotate') do
    it { should be_installed }
  end
end

control 'pkg-mcstrans-removed' do
  impact 0.3
  title 'Uninstall mcstrans Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '1.3.1.7'
  tag level_cis: '1'
  tag ssg: 'package_mcstrans_removed'
  describe package('mcstrans') do
    it { should_not be_installed }
  end
end

control 'pkg-net-snmp-removed' do
  impact 0.5
  title 'Uninstall net-snmp Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.14'
  tag('pci-dss' => '2.2.4')
  tag level_cis: '1'
  tag ssg: 'package_net-snmp_removed'
  describe package('net-snmp') do
    it { should_not be_installed }
  end
end

control 'pkg-nginx-removed' do
  impact 0.5
  title 'Uninstall nginx Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.18'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'package_nginx_removed'
  describe package('nginx') do
    it { should_not be_installed }
  end
end

control 'pkg-nis-removed' do
  impact 0.3
  title 'Uninstall the nis package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_nis_removed'
  describe package('nis') do
    it { should_not be_installed }
  end
end

control 'pkg-openldap-clients-removed' do
  impact 0.3
  title 'Ensure LDAP client is not installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.2.2'
  tag level_cis: '2'
  tag ssg: 'package_openldap-clients_removed'
  describe package('openldap-clients') do
    it { should_not be_installed }
  end
end

control 'pkg-pam-pwquality-installed' do
  impact 0.5
  title 'Install pam_pwquality Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.3.1.3'
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'package_pam_pwquality_installed'
  describe package('libpam-pwquality') do
    it { should be_installed }
  end
end

control 'pkg-postfix-installed' do
  impact 0.5
  title 'The Postfix package is installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '6.3.2.4'
  tag('pci-dss' => '10.5.1')
  tag level_cis: '2'
  tag ssg: 'package_postfix_installed'
  describe package('postfix') do
    it { should be_installed }
  end
end

control 'pkg-rsh-client-removed' do
  impact 1.0
  title 'Uninstall rsh Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag nist: '3.1.13'
  tag level_bp28: 'minimal'
  tag ssg: 'package_rsh_removed'
  describe package('rsh-client') do
    it { should_not be_installed }
  end
end

control 'pkg-rsh-server-removed' do
  impact 1.0
  title 'Uninstall rsh-server Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'IA-5(1)(c)']
  tag level_bp28: 'minimal'
  tag ssg: 'package_rsh-server_removed'
  describe package('rsh-server') do
    it { should_not be_installed }
  end
end

control 'pkg-rsync-removed' do
  impact 0.5
  title 'Uninstall rsync Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.13'
  tag level_cis: '1'
  tag ssg: 'package_rsync_removed'
  describe package('rsync-daemon') do
    it { should_not be_installed }
  end
end

control 'pkg-samba-removed' do
  impact 0.5
  title 'Uninstall Samba Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.6'
  tag level_cis: '1'
  tag ssg: 'package_samba_removed'
  describe package('samba') do
    it { should_not be_installed }
  end
end

control 'pkg-sendmail-removed' do
  impact 0.5
  title 'Uninstall Sendmail Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag ssg: 'package_sendmail_removed'
  describe package('sendmail') do
    it { should_not be_installed }
  end
end

control 'pkg-setroubleshoot-plugins-removed' do
  impact 0.3
  title 'Uninstall setroubleshoot-plugins Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R49'
  tag level_bp28: 'high'
  tag ssg: 'package_setroubleshoot-plugins_removed'
  describe package('setroubleshoot-plugins') do
    it { should_not be_installed }
  end
end

control 'pkg-setroubleshoot-removed' do
  impact 0.3
  title 'Uninstall setroubleshoot Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R49'
  tag cis: '1.3.1.8'
  tag level_bp28: 'high'
  tag level_cis: '1'
  tag ssg: 'package_setroubleshoot_removed'
  describe package('setroubleshoot') do
    it { should_not be_installed }
  end
end

control 'pkg-setroubleshoot-server-removed' do
  impact 0.3
  title 'Uninstall setroubleshoot-server Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R49'
  tag level_bp28: 'high'
  tag ssg: 'package_setroubleshoot-server_removed'
  describe package('setroubleshoot-server') do
    it { should_not be_installed }
  end
end

control 'pkg-squid-removed' do
  impact 0.5
  title 'Uninstall squid Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.17'
  tag level_cis: '1'
  tag ssg: 'package_squid_removed'
  describe package('squid') do
    it { should_not be_installed }
  end
end

control 'pkg-sssd-installed' do
  impact 0.5
  title 'Install the SSSD Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R67'
  tag nist: 'CM-6(a)'
  tag level_bp28: 'intermediary'
  tag ssg: 'package_sssd_installed'
  describe package('sssd') do
    it { should be_installed }
  end
end

control 'pkg-sudo-installed' do
  impact 0.5
  title 'Install sudo Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R33'
  tag('pci-dss' => '2.2.6')
  tag nist: 'CM-6(a)'
  tag level_bp28: 'intermediary'
  tag ssg: 'package_sudo_installed'
  describe package('sudo') do
    it { should be_installed }
  end
end

control 'pkg-systemd-journal-remote-installed' do
  impact 0.5
  title 'Install systemd-journal-remote Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '6.2.2.1.1'
  tag level_cis: '1'
  tag ssg: 'package_systemd-journal-remote_installed'
  describe package('systemd-journal-remote') do
    it { should be_installed }
  end
end

control 'pkg-talk-removed' do
  impact 0.5
  title 'Uninstall talk Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag level_bp28: 'minimal'
  tag ssg: 'package_talk_removed'
  describe package('talk') do
    it { should_not be_installed }
  end
end

control 'pkg-talkd-removed' do
  impact 1.0
  title 'Uninstall talk-server Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag level_bp28: 'minimal'
  tag ssg: 'package_talk-server_removed'
  describe package('talkd') do
    it { should_not be_installed }
  end
end

control 'pkg-telnet-removed' do
  impact 0.3
  title 'Remove telnet Clients'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag nist: '3.1.13'
  tag level_bp28: 'minimal'
  tag ssg: 'package_telnet_removed'
  describe package('telnet') do
    it { should_not be_installed }
  end
end

control 'pkg-telnet-server-removed' do
  impact 1.0
  title 'Uninstall telnet-server Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag ssg: 'package_telnet-server_removed'
  describe package('telnet-server') do
    it { should_not be_installed }
  end
end

control 'pkg-telnetd-removed' do
  impact 0.7
  title 'Uninstall the telnet server'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_telnetd_removed'
  describe package('telnetd') do
    it { should_not be_installed }
  end
end

control 'pkg-telnetd-ssl-removed' do
  impact 0.7
  title 'Uninstall the ssl compliant telnet server'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_telnetd-ssl_removed'
  describe package('telnetd-ssl') do
    it { should_not be_installed }
  end
end

control 'pkg-tftp-removed' do
  impact 0.3
  title 'Remove tftp Daemon'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag level_bp28: 'minimal'
  tag ssg: 'package_tftp_removed'
  describe package('tftp') do
    it { should_not be_installed }
  end
end

control 'pkg-tftp-server-removed' do
  impact 1.0
  title 'Uninstall tftp-server Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag ssg: 'package_tftp-server_removed'
  describe package('tftp-server') do
    it { should_not be_installed }
  end
end

control 'pkg-vsftpd-removed' do
  impact 0.7
  title 'Uninstall vsftpd Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.7'
  tag nist: ['CM-6(a)', 'CM-7', 'CM-7(a)', 'CM-7(b)', 'IA-5(1)(c)', 'IA-5(1).1(v)']
  tag level_cis: '1'
  tag ssg: 'package_vsftpd_removed'
  describe package('vsftpd') do
    it { should_not be_installed }
  end
end

control 'pkg-xinetd-removed' do
  impact 0.3
  title 'Uninstall xinetd package if not used by network services'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag ssg: 'package_xinetd_removed'
  describe package('xinetd') do
    it { should_not be_installed }
  end
end

control 'pkg-xorg-x11-server-common-removed' do
  impact 0.5
  title 'Remove the X Windows Package Group'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.20'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'package_xorg-x11-server-common_removed'
  describe package('xorg-x11-server-common') do
    it { should_not be_installed }
  end
end

control 'pkg-ypserv-removed' do
  impact 1.0
  title 'Uninstall ypserv Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'IA-5(1)(c)']
  tag level_bp28: 'minimal'
  tag ssg: 'package_ypserv_removed'
  describe package('ypserv') do
    it { should_not be_installed }
  end
end
