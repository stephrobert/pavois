# Rendered from pavois reference (pavois-content/almalinux9.yml). Do not edit by hand.

control 'misc-account-unique-id' do
  impact 0.5
  title 'Ensure All Accounts on the System Have Unique User IDs'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.2.4'
  tag('pci-dss' => '8.2.1')
  tag level_cis: '1'
  tag ssg: 'account_unique_id'
  describe command('awk -F: \'($3 in s){print $3}{s[$3]}\' /etc/passwd') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-accounts-tmout' do
  impact 0.5
  title 'Set Interactive Session Timeout'
  tag domain: 'Hardening (misc)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R32'
  tag cis: '5.4.3.2'
  tag('pci-dss' => '8.6.1')
  tag nist: ['3.1.11', 'AC-12', 'AC-2(5)', 'CM-6(a)', 'SC-10']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'accounts_tmout'
  describe command('grep -qrE \'^[^#]*TMOUT=[0-9]\' /etc/profile /etc/profile.d/ /etc/bashrc 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-aide-build-database' do
  impact 0.5
  title 'Build and Test AIDE Database'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R76'
  tag cis: '6.1.1'
  tag('pci-dss' => '11.5.2')
  tag nist: 'CM-6(a)'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'aide_build_database'
  describe command('command -v aide >/dev/null 2>&1 && ls /var/lib/aide/aide.db* >/dev/null 2>&1 && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-disable-host-auth' do
  impact 0.5
  title 'Disable Host-Based Authentication'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.12'
  tag('pci-dss' => '8.3.1')
  tag nist: ['3.1.12', 'AC-17(a)', 'AC-3', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'disable_host_auth'
  describe command('sshd -T 2>/dev/null | grep -qiE \'^hostbasedauthentication no\' && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-ensure-pam-wheel-group-empty' do
  impact 0.5
  title 'Ensure the Group Used by pam_wheel.so Module Exists on System and is Empty'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.2.7'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'ensure_pam_wheel_group_empty'
  describe command('g=$(grep -rhoE \'pam_wheel.so.*group=[a-z]+\' /etc/pam.d/su 2>/dev/null | grep -oE \'group=[a-z]+\' | cut -d= -f2 | head -1); { [ -n "$g" ] && [ -z "$(getent group "$g" | cut -d: -f4)" ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-group-unique-id' do
  impact 0.5
  title 'Ensure All Groups on the System Have Unique Group ID'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.2.5'
  tag('pci-dss' => '8.2.1')
  tag level_cis: '1'
  tag ssg: 'group_unique_id'
  describe command('awk -F: \'($3 in s){print $3}{s[$3]}\' /etc/group') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-no-direct-root-logins' do
  impact 0.5
  title 'Direct root Logins Not Allowed'
  tag domain: 'Hardening (misc)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R33'
  tag('pci-dss' => '8.6.1')
  tag nist: ['3.1.1', 'CM-6(a)', 'IA-2']
  tag level_bp28: 'intermediary'
  tag ssg: 'no_direct_root_logins'
  describe command('[ -s /etc/securetty ] && echo ko || echo ok') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-no-forward-files' do
  impact 0.5
  title 'Verify No .forward Files Exist'
  tag domain: 'Hardening (misc)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.2.9'
  tag level_cis: '1'
  tag ssg: 'no_forward_files'
  describe command('find /root /home -xdev -name .forward 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-no-netrc-files' do
  impact 0.5
  title 'Verify No netrc Files Exist'
  tag domain: 'Hardening (misc)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.2.9'
  tag nist: ['CM-6(a)', 'IA-5(1)(c)', 'IA-5(7)', 'IA-5(h)']
  tag level_cis: '1'
  tag ssg: 'no_netrc_files'
  describe command('find /root /home -xdev -name .netrc 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-no-rsh-trust-files' do
  impact 0.7
  title 'Remove Rsh Trust Files'
  tag domain: 'Hardening (misc)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.2.9'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'no_rsh_trust_files'
  describe command('find /root /home -xdev -name .rhosts 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-no-shelllogin-for-systemaccounts' do
  impact 0.5
  title 'Ensure that System Accounts Do Not Run a Shell Upon Login'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.4.2.7'
  tag('pci-dss' => '8.2.2')
  tag nist: ['AC-6', 'CM-6', 'CM-6(a)', 'CM-6(b)']
  tag level_cis: '1'
  tag ssg: 'no_shelllogin_for_systemaccounts'
  describe command('awk -F: \'($3<1000 && $1!="root" && $7 !~ /nologin|false|sync|shutdown|halt/){print $1}\' /etc/passwd') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-postfix-network-listening-disabled' do
  impact 0.5
  title 'Disable Postfix Network Listening'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R74'
  tag cis: '2.1.21'
  tag('pci-dss' => '1.4.2')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'postfix_network_listening_disabled'
  describe command('postconf -h inet_interfaces 2>/dev/null | grep -qiE \'loopback-only|localhost\' && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-prefer-64bit-os' do
  impact 0.5
  title 'Prefer to use a 64-bit Operating System when supported'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R1'
  tag level_bp28: 'enhanced'
  tag ssg: 'prefer_64bit_os'
  describe command('uname -m | grep -qE \'x86_64|aarch64|amd64|s390x\' && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-set-password-hashing-algorithm' do
  impact 0.5
  title 'Set PAM Password Hashing Algorithm - password-auth'
  tag domain: 'Hardening (misc)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R68'
  tag cis: '5.3.3.4.3'
  tag('pci-dss' => '8.3.2')
  tag nist: ['3.13.11', 'CM-6(a)', 'IA-5(1)(c)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'set_password_hashing_algorithm_passwordauth'
  describe command('grep -qrE \'pam_unix.so.*(sha512|yescrypt)\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-sshd-limit-user-access' do
  impact 0.5
  title 'Limit Users\' SSH Access'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.7'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.1.12', 'AC-3', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'sshd_limit_user_access'
  describe command('sshd -T 2>/dev/null | grep -qiE \'^(allowusers|allowgroups|denyusers|denygroups) .\' && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-sssd-ldap-configure-tls-reqcert' do
  impact 0.5
  title 'Configure SSSD LDAP Backend Client to Demand a Valid Certificate from the Server'
  tag domain: 'Hardening (misc)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R67'
  tag nist: ['CM-6(a)', 'SC-12(3)']
  tag level_bp28: 'intermediary'
  tag ssg: 'sssd_ldap_configure_tls_reqcert'
  describe command('grep -qriE \'^[[:space:]]*ldap_tls_reqcert[[:space:]]*=[[:space:]]*(demand|hard)\' /etc/sssd/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-sssd-ldap-start-tls' do
  impact 0.7
  title 'Configure SSSD LDAP Backend to Use TLS For All Transactions'
  tag domain: 'Hardening (misc)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R67'
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'intermediary'
  tag ssg: 'sssd_ldap_start_tls'
  only_if { file('/etc/sssd/sssd.conf').exist? }
  describe command('grep -qriE \'^[[:space:]]*ldap_id_use_start_tls[[:space:]]*=[[:space:]]*true\' /etc/sssd/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-use-pam-wheel-group-for-su' do
  impact 0.5
  title 'Enforce Usage of pam_wheel with Group Parameter for su Authentication'
  tag domain: 'Hardening (misc)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.2.7'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'use_pam_wheel_group_for_su'
  describe command('grep -qrE \'^[^#]*pam_wheel.so.*use_uid\' /etc/pam.d/su 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-wireless-disable-interfaces' do
  impact 0.5
  title 'Deactivate Wireless Network Interfaces'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '3.1.2'
  tag('pci-dss' => '1.3.3')
  tag nist: ['3.1.16', 'AC-18(3)', 'AC-18(a)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'wireless_disable_interfaces'
  describe command('nmcli radio all 2>/dev/null | grep -qiw enabled && echo ko || echo ok') do
    its('stdout.strip') { should eq 'ok' }
  end
end
