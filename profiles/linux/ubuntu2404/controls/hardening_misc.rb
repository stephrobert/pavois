# Rendered from pavois reference (pavois-content/ubuntu2404.yml). Do not edit by hand.

control 'misc-account-unique-id' do
  impact 0.5
  title 'Ensure All Accounts on the System Have Unique User IDs'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: ['7.2.5', '8.2.1']
  tag('pci-dss' => 'Req-8.1.1')
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
  tag cis: ['5.4.3.2', '8.6.1']
  tag('pci-dss' => '8.6.1')
  tag nist: ['3.1.11', 'AC-12', 'AC-2(5)', 'CM-6(a)', 'SC-10']
  tag stig: 'UBTU-24-200060'
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
  tag cis: ['11.5.2', '6.3.1']
  tag('pci-dss' => 'Req-11.5')
  tag nist: 'CM-6(a)'
  tag stig: 'UBTU-24-100110'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'aide_build_database'
  describe command('command -v aide >/dev/null 2>&1 && ls /var/lib/aide/aide.db* >/dev/null 2>&1 && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-aide-periodic-checking-systemd-timer' do
  impact 0.5
  title 'Configure Systemd Timer Execution of AIDE'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R76'
  tag cis: ['11.5.2', '6.3.2']
  tag('pci-dss' => 'Req-11.5')
  tag nist: ['SI-7', 'SI-7(1)', 'CM-6(a)']
  tag stig: 'UBTU-24-100120'
  tag level_bp28: 'high'
  tag level_cis: '1'
  tag ssg: 'aide_periodic_checking_systemd_timer'
  describe command('systemctl is-enabled aidecheck.timer dailyaidecheck.timer 2>/dev/null | grep -q enabled && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-all-apparmor-profiles-enforced' do
  impact 0.5
  title 'Enforce all AppArmor Profiles'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R45'
  tag cis: '1.3.1.4'
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'all_apparmor_profiles_enforced'
  describe command('[ "$(aa-status --complaining 2>/dev/null)" = "0" ] && [ -n "$(aa-status --enabled 2>/dev/null && echo y)" ] && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-all-apparmor-profiles-in-enforce-complain-mode' do
  impact 0.5
  title 'All AppArmor Profiles are in enforce or complain mode'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '1.3.1.3'
  tag level_cis: '1'
  tag ssg: 'all_apparmor_profiles_in_enforce_complain_mode'
  describe command('aa-status 2>/dev/null | grep -qi \'profiles are loaded\' && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-apparmor-configured' do
  impact 0.5
  title 'Ensure AppArmor is Active and Configured'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R45'
  tag nist: ['AC-3(4)', 'AC-6(8)', 'AC-6(10)', 'CM-7(5)(b)', 'CM-7(2)', 'SC-7(21)', 'CM-6(a)']
  tag stig: 'UBTU-24-100510'
  tag level_bp28: 'enhanced'
  tag ssg: 'apparmor_configured'
  describe command('aa-status 2>/dev/null | grep -qi \'module is loaded\' && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-disable-host-auth' do
  impact 0.5
  title 'Disable Host-Based Authentication'
  tag domain: 'Hardening (misc)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: ['5.1.10', '8.3.1']
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
  tag cis: ['2.2.6', '5.2.7']
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'ensure_pam_wheel_group_empty'
  describe command('g=$(grep -rhoE \'pam_wheel.so.*group=[a-z]+\' /etc/pam.d/su 2>/dev/null | grep -oE \'group=[a-z]+\' | cut -d= -f2 | head -1); { [ -n "$g" ] && [ -z "$(getent group "$g" | cut -d: -f4)" ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-ensure-shadow-group-empty' do
  impact 0.5
  title 'Ensure shadow Group is Empty'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: ['7.2.4', '8.3.2']
  tag('pci-dss' => 'Req-8.2.1')
  tag level_cis: '1'
  tag ssg: 'ensure_shadow_group_empty'
  describe command('awk -F: \'($1=="shadow"){print $4}\' /etc/group') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-group-unique-id' do
  impact 0.5
  title 'Ensure All Groups on the System Have Unique Group ID'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: ['7.2.6', '8.2.1']
  tag('pci-dss' => '8.2.1')
  tag level_cis: '1'
  tag ssg: 'group_unique_id'
  describe command('awk -F: \'($3 in s){print $3}{s[$3]}\' /etc/group') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-groups-no-zero-gid-except-root' do
  impact 0.7
  title 'Verify Only Group Root Has GID 0'
  tag domain: 'Hardening (misc)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.4.2.3'
  tag level_cis: '1'
  tag ssg: 'groups_no_zero_gid_except_root'
  describe command('awk -F: \'($3==0 && $1!="root"){print $1}\' /etc/group') do
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
  tag cis: '5.4.2.4'
  tag('pci-dss' => '8.6.1')
  tag nist: ['3.1.1', 'CM-6(a)', 'IA-2']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
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
  tag cis: '7.2.10'
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
  tag cis: '7.2.10'
  tag nist: ['CM-6(a)', 'IA-5(1)(c)', 'IA-5(7)', 'IA-5(h)']
  tag level_cis: '1'
  tag ssg: 'no_netrc_files'
  describe command('find /root /home -xdev -name .netrc 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'misc-no-nologin-in-shells' do
  impact 0.5
  title 'Ensure nologin Shell is Not Listed in /etc/shells'
  tag domain: 'Hardening (misc)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.4.3.1'
  tag level_cis: '2'
  tag ssg: 'no_nologin_in_shells'
  describe command('grep -qE \'nologin|/bin/false\' /etc/shells 2>/dev/null && echo ko || echo ok') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'misc-no-rsh-trust-files' do
  impact 0.7
  title 'Remove Rsh Trust Files'
  tag domain: 'Hardening (misc)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.2.10'
  tag nist: ['CM-7(a)', 'CM-7(b)', 'CM-6(a)']
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
  tag cis: ['5.4.2.7', '8.2.2']
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
  tag cis: ['1.4.2', '2.1.21']
  tag('pci-dss' => '1.4.2')
  tag nist: ['CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'postfix_network_listening_disabled'
  only_if { command('command -v postconf').exit_status.zero? }
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
  title 'Set PAM Password Hashing Algorithm - system-auth'
  tag domain: 'Hardening (misc)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R68'
  tag cis: ['5.3.3.4.3', '8.3.2']
  tag('pci-dss' => 'Req-8.2.1')
  tag nist: ['3.13.11', 'CM-6(a)', 'IA-5(1)(c)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'set_password_hashing_algorithm_systemauth'
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
  tag cis: ['2.2.6', '5.1.4']
  tag('pci-dss' => 'Req-2.2.4')
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
  only_if { command('test -f /etc/sssd/sssd.conf').exit_status.zero? }
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
  tag cis: ['2.2.6', '5.2.7']
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
  tag cis: ['1.3.3', '3.1.2']
  tag('pci-dss' => 'Req-1.3.3')
  tag nist: ['3.1.16', 'AC-18(3)', 'AC-18(a)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag stig: 'UBTU-24-600230'
  tag level_cis: '1'
  tag ssg: 'wireless_disable_interfaces'
  describe command('nmcli radio all 2>/dev/null | grep -qiw enabled && echo ko || echo ok') do
    its('stdout.strip') { should eq 'ok' }
  end
end
