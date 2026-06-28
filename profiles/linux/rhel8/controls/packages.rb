# Rendered from pavois reference (pavois-content/rhel8.yml). Do not edit by hand.

control 'pkg-abrt-addon-ccpp-removed' do
  impact 0.3
  title 'Uninstall abrt-addon-ccpp Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_abrt-addon-ccpp_removed'
  describe package('abrt-addon-ccpp') do
    it { should_not be_installed }
  end
end

control 'pkg-abrt-addon-kerneloops-removed' do
  impact 0.3
  title 'Uninstall abrt-addon-kerneloops Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_abrt-addon-kerneloops_removed'
  describe package('abrt-addon-kerneloops') do
    it { should_not be_installed }
  end
end

control 'pkg-abrt-cli-removed' do
  impact 0.3
  title 'Uninstall abrt-cli Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_abrt-cli_removed'
  describe package('abrt-cli') do
    it { should_not be_installed }
  end
end

control 'pkg-abrt-plugin-sosreport-removed' do
  impact 0.3
  title 'Uninstall abrt-plugin-sosreport Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_abrt-plugin-sosreport_removed'
  describe package('abrt-plugin-sosreport') do
    it { should_not be_installed }
  end
end

control 'pkg-abrt-removed' do
  impact 0.5
  title 'Uninstall Automatic Bug Reporting Tool (abrt)'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_abrt_removed'
  describe package('abrt') do
    it { should_not be_installed }
  end
end

control 'pkg-aide-installed' do
  impact 0.5
  title 'Install AIDE'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R76'
  tag cis: '6.1.1'
  tag('pci-dss' => '11.5.2')
  tag nist: 'CM-6(a)'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'package_aide_installed'
  describe package('aide') do
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
  describe package('audit') do
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
  describe package('audit-libs') do
    it { should be_installed }
  end
end

control 'pkg-authselect-installed' do
  impact 0.5
  title 'Install authselect Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.3.1.2'
  tag level_cis: '1'
  tag ssg: 'package_authselect_installed'
  describe package('authselect') do
    it { should be_installed }
  end
end

control 'pkg-bind-removed' do
  impact 0.3
  title 'Uninstall bind Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.5'
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
  tag cis: '2.4.1.1'
  tag('pci-dss' => '2.2.6')
  tag nist: 'CM-6(a)'
  tag level_cis: '1'
  tag ssg: 'package_cron_installed'
  describe package('cronie') do
    it { should be_installed }
  end
end

control 'pkg-crypto-policies-installed' do
  impact 0.5
  title 'Install crypto-policies package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_crypto-policies_installed'
  describe package('crypto-policies') do
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
  tag cis: '2.1.4'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'package_dhcp_removed'
  describe package('dhcp-server') do
    it { should_not be_installed }
  end
end

control 'pkg-dnf-automatic-installed' do
  impact 0.5
  title 'Install dnf-automatic Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R61'
  tag level_bp28: 'minimal'
  tag ssg: 'package_dnf-automatic_installed'
  describe package('dnf-automatic') do
    it { should be_installed }
  end
end

control 'pkg-dnf-plugin-subscription-manager-installed' do
  impact 0.5
  title 'Install dnf-plugin-subscription-manager Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_dnf-plugin-subscription-manager_installed'
  describe package('dnf-plugin-subscription-manager') do
    it { should be_installed }
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

control 'pkg-fapolicyd-installed' do
  impact 0.5
  title 'Install fapolicyd Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_fapolicyd_installed'
  describe package('fapolicyd') do
    it { should be_installed }
  end
end

control 'pkg-firewalld-installed' do
  impact 0.5
  title 'Install firewalld Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '4.1.1'
  tag('pci-dss' => '1.2.1')
  tag level_cis: '1'
  tag ssg: 'package_firewalld_installed'
  describe package('firewalld') do
    it { should be_installed }
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
  tag cis: '2.1.21'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'package_gdm_removed'
  describe package('gdm') do
    it { should_not be_installed }
  end
end

control 'pkg-gnutls-utils-installed' do
  impact 0.5
  title 'Ensure gnutls-utils is installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_gnutls-utils_installed'
  describe package('gnutls-utils') do
    it { should be_installed }
  end
end

control 'pkg-gssproxy-removed' do
  impact 0.5
  title 'Uninstall gssproxy Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_gssproxy_removed'
  describe package('gssproxy') do
    it { should_not be_installed }
  end
end

control 'pkg-httpd-removed' do
  impact 0.5
  title 'Uninstall httpd Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.19'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'package_httpd_removed'
  describe package('httpd') do
    it { should_not be_installed }
  end
end

control 'pkg-iprutils-removed' do
  impact 0.5
  title 'Uninstall iprutils Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_iprutils_removed'
  describe package('iprutils') do
    it { should_not be_installed }
  end
end

control 'pkg-krb5-server-removed' do
  impact 0.5
  title 'Remove the Kerberos Server Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_krb5-server_removed'
  describe package('krb5-server') do
    it { should_not be_installed }
  end
end

control 'pkg-krb5-workstation-removed' do
  impact 0.5
  title 'Uninstall krb5-workstation Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_krb5-workstation_removed'
  describe package('krb5-workstation') do
    it { should_not be_installed }
  end
end

control 'pkg-libreport-plugin-logger-removed' do
  impact 0.3
  title 'Uninstall libreport-plugin-logger Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_libreport-plugin-logger_removed'
  describe package('libreport-plugin-logger') do
    it { should_not be_installed }
  end
end

control 'pkg-libreport-plugin-rhtsupport-removed' do
  impact 0.3
  title 'Uninstall libreport-plugin-rhtsupport Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_libreport-plugin-rhtsupport_removed'
  describe package('libreport-plugin-rhtsupport') do
    it { should_not be_installed }
  end
end

control 'pkg-libselinux-installed' do
  impact 0.7
  title 'Install libselinux Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '1.3.1.1'
  tag('pci-dss' => '1.2.6')
  tag level_cis: '1'
  tag ssg: 'package_libselinux_installed'
  describe package('libselinux') do
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

control 'pkg-mailx-installed' do
  impact 0.5
  title 'The mailx Package Is Installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_mailx_installed'
  describe package('mailx') do
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
  tag cis: '2.1.15'
  tag('pci-dss' => '2.2.4')
  tag level_cis: '1'
  tag ssg: 'package_net-snmp_removed'
  describe package('net-snmp') do
    it { should_not be_installed }
  end
end

control 'pkg-nfs-utils-removed' do
  impact 0.3
  title 'Uninstall nfs-utils Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_nfs-utils_removed'
  describe package('nfs-utils') do
    it { should_not be_installed }
  end
end

control 'pkg-nginx-removed' do
  impact 0.5
  title 'Uninstall nginx Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.19'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'package_nginx_removed'
  describe package('nginx') do
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

control 'pkg-opensc-installed' do
  impact 0.5
  title 'Install the opensc Package For Multifactor Authentication'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_opensc_installed'
  describe package('opensc') do
    it { should be_installed }
  end
end

control 'pkg-openscap-scanner-installed' do
  impact 0.5
  title 'Install openscap-scanner Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_openscap-scanner_installed'
  describe package('openscap-scanner') do
    it { should be_installed }
  end
end

control 'pkg-openssh-clients-installed' do
  impact 0.5
  title 'Install OpenSSH client software'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_openssh-clients_installed'
  describe package('openssh-clients') do
    it { should be_installed }
  end
end

control 'pkg-openssh-server-installed' do
  impact 0.5
  title 'Install the OpenSSH Server Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_openssh-server_installed'
  describe package('openssh-server') do
    it { should be_installed }
  end
end

control 'pkg-pam-installed' do
  impact 0.5
  title 'Install pam Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.3.1.1'
  tag level_cis: '1'
  tag ssg: 'package_pam_installed'
  describe package('pam') do
    it { should be_installed }
  end
end

control 'pkg-pam-pwquality-installed' do
  impact 0.5
  title 'Install pam_pwquality Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.3.2.3'
  tag level_cis: '1'
  tag ssg: 'package_pam_pwquality_installed'
  describe package('libpwquality') do
    it { should be_installed }
  end
end

control 'pkg-policycoreutils-installed' do
  impact 0.3
  title 'Install policycoreutils Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_policycoreutils_installed'
  describe package('policycoreutils') do
    it { should be_installed }
  end
end

control 'pkg-policycoreutils-python-utils-installed' do
  impact 0.5
  title 'Install policycoreutils-python-utils package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_policycoreutils-python-utils_installed'
  describe package('policycoreutils-python-utils') do
    it { should be_installed }
  end
end

control 'pkg-postfix-installed' do
  impact 0.5
  title 'The Postfix package is installed'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag('pci-dss' => '10.5.1')
  tag ssg: 'package_postfix_installed'
  describe package('postfix') do
    it { should be_installed }
  end
end

control 'pkg-python3-abrt-addon-removed' do
  impact 0.3
  title 'Uninstall python3-abrt-addon Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_python3-abrt-addon_removed'
  describe package('python3-abrt-addon') do
    it { should_not be_installed }
  end
end

control 'pkg-rear-installed' do
  impact 0.5
  title 'Install rear Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_rear_installed'
  describe package('rear') do
    it { should be_installed }
  end
end

control 'pkg-rng-tools-installed' do
  impact 0.3
  title 'Install rng-tools Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_rng-tools_installed'
  describe package('rng-tools') do
    it { should be_installed }
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
  tag cis: '2.1.14'
  tag level_cis: '1'
  tag ssg: 'package_samba_removed'
  describe package('samba') do
    it { should_not be_installed }
  end
end

control 'pkg-scap-security-guide-installed' do
  impact 0.5
  title 'Install scap-security-guide Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_scap-security-guide_installed'
  describe package('scap-security-guide') do
    it { should be_installed }
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
  tag cis: '2.1.18'
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

control 'pkg-subscription-manager-installed' do
  impact 0.5
  title 'Install subscription-manager Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_subscription-manager_installed'
  describe package('subscription-manager') do
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
  tag cis: '5.2.1'
  tag('pci-dss' => '2.2.6')
  tag nist: 'CM-6(a)'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
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
  tag cis: '6.2.1.2.1'
  tag level_cis: '1'
  tag ssg: 'package_systemd-journal-remote_installed'
  describe package('systemd-journal-remote') do
    it { should be_installed }
  end
end

control 'pkg-telnet-removed' do
  impact 0.3
  title 'Remove telnet Clients'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag cis: '2.2.4'
  tag('pci-dss' => '2.2.4')
  tag nist: '3.1.13'
  tag level_bp28: 'minimal'
  tag level_cis: '1'
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
  tag cis: '2.1.16'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'package_telnet-server_removed'
  describe package('telnet-server') do
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
  tag cis: '2.2.5'
  tag('pci-dss' => '2.2.4')
  tag level_bp28: 'minimal'
  tag level_cis: '1'
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
  tag cis: '2.1.17'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'package_tftp-server_removed'
  describe package('tftp-server') do
    it { should_not be_installed }
  end
end

control 'pkg-tmux-installed' do
  impact 0.5
  title 'Install the tmux Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag nist: '3.1.10'
  tag ssg: 'package_tmux_installed'
  describe package('tmux') do
    it { should be_installed }
  end
end

control 'pkg-tuned-removed' do
  impact 0.5
  title 'Uninstall tuned Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_tuned_removed'
  describe package('tuned') do
    it { should_not be_installed }
  end
end

control 'pkg-usbguard-installed' do
  impact 0.5
  title 'Install usbguard Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag ssg: 'package_usbguard_installed'
  describe package('usbguard') do
    it { should be_installed }
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
  tag cis: '2.1.20'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'package_xinetd_removed'
  describe package('xinetd') do
    it { should_not be_installed }
  end
end

control 'pkg-xorg-x11-server-Xwayland-removed' do
  impact 0.5
  title 'Remove the X Windows Xwayland Package'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '2.1.22'
  tag level_cis: '2'
  tag ssg: 'package_xorg-x11-server-Xwayland_removed'
  describe package('xorg-x11-server-Xwayland') do
    it { should_not be_installed }
  end
end

control 'pkg-ypbind-removed' do
  impact 0.5
  title 'Remove NIS Client'
  tag domain: 'Packages'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R62'
  tag cis: '2.2.3'
  tag('pci-dss' => '2.2.4')
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'package_ypbind_removed'
  describe package('ypbind') do
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
  tag cis: '2.1.10'
  tag('pci-dss' => '2.2.4')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'IA-5(1)(c)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'package_ypserv_removed'
  describe package('ypserv') do
    it { should_not be_installed }
  end
end
