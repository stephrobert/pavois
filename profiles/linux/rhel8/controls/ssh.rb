# Rendered from pavois reference (pavois-content/rhel8.yml). Do not edit by hand.

control 'ssh-disable-compression' do
  impact 0.5
  title 'Disable Compression Or Set Compression to delayed'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: '3.1.12'
  tag ssg: 'sshd_disable_compression'
  describe command('sshd -T') do
    its('stdout') { should match(/^compression\s+no$/i) }
  end
end

control 'ssh-disable-empty-passwords' do
  impact 1.0
  title 'Disable SSH Access via Empty Passwords'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.21'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.1.1', 'AC-17(a)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'sshd_disable_empty_passwords'
  describe command('sshd -T') do
    its('stdout') { should match(/^permitemptypasswords\s+no$/i) }
  end
end

control 'ssh-disable-forwarding' do
  impact 0.5
  title 'Disable SSH Forwarding'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.10'
  tag level_cis: '2'
  tag ssg: 'sshd_disable_forwarding'
  describe command('sshd -T') do
    its('stdout') { should match(/^disableforwarding\s+yes$/i) }
  end
end

control 'ssh-disable-gssapi-auth' do
  impact 0.5
  title 'Disable GSSAPI Authentication'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.11'
  tag nist: ['3.1.12', 'AC-17(a)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '2'
  tag ssg: 'sshd_disable_gssapi_auth'
  describe command('sshd -T') do
    its('stdout') { should match(/^gssapiauthentication\s+no$/i) }
  end
end

control 'ssh-disable-kerb-auth' do
  impact 0.5
  title 'Disable Kerberos Authentication'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: '3.1.12'
  tag ssg: 'sshd_disable_kerb_auth'
  describe command('sshd -T') do
    its('stdout') { should match(/^kerberosauthentication\s+no$/i) }
  end
end

control 'ssh-disable-rhosts' do
  impact 0.5
  title 'Disable SSH Support for .rhosts Files'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.13'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.1.12', 'AC-17(a)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'sshd_disable_rhosts'
  describe command('sshd -T') do
    its('stdout') { should match(/^ignorerhosts\s+yes$/i) }
  end
end

control 'ssh-disable-root-login' do
  impact 1.0
  title 'Disable SSH Root Login'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R33'
  tag cis: '5.1.22'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.1.1', 'AC-17(a)', 'AC-6(2)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'IA-2', 'IA-2(5)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sshd_disable_root_login'
  describe command('sshd -T') do
    its('stdout') { should match(/^permitrootlogin\s+no$/i) }
  end
end

control 'ssh-disable-user-known-hosts' do
  impact 0.5
  title 'Disable SSH Support for User Known Hosts'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: '3.1.12'
  tag ssg: 'sshd_disable_user_known_hosts'
  describe command('sshd -T') do
    its('stdout') { should match(/^ignoreuserknownhosts\s+yes$/i) }
  end
end

control 'ssh-do-not-permit-user-env' do
  impact 0.5
  title 'Do Not Allow SSH Environment Options'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.23'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.1.12', 'AC-17(a)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'sshd_do_not_permit_user_env'
  describe command('sshd -T') do
    its('stdout') { should match(/^permituserenvironment\s+no$/i) }
  end
end

control 'ssh-enable-pam' do
  impact 0.5
  title 'Enable PAM'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.24'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'sshd_enable_pam'
  describe command('sshd -T') do
    its('stdout') { should match(/^usepam\s+yes$/i) }
  end
end

control 'ssh-enable-strictmodes' do
  impact 0.5
  title 'Enable Use of Strict Mode Checking'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: '3.1.12'
  tag ssg: 'sshd_enable_strictmodes'
  describe command('sshd -T') do
    its('stdout') { should match(/^strictmodes\s+yes$/i) }
  end
end

control 'ssh-enable-warning-banner' do
  impact 0.5
  title 'Enable SSH Warning Banner'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag nist: '3.1.9'
  tag ssg: 'sshd_enable_warning_banner'
  describe command('sshd -T') do
    its('stdout') { should match(/^banner\s+\/etc\/issue$/i) }
  end
end

control 'ssh-enable-warning-banner-net' do
  impact 0.5
  title 'Enable SSH Warning Banner'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.7'
  tag nist: ['3.1.9', 'AC-17(a)', 'AC-8(a)', 'AC-8(c)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'sshd_enable_warning_banner_net'
  describe command('sshd -T') do
    its('stdout') { should match(/^banner\s+\/etc\/issue\.net$/i) }
  end
end

control 'ssh-print-last-log' do
  impact 0.5
  title 'Enable SSH Print Last Log'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'sshd_print_last_log'
  describe command('sshd -T') do
    its('stdout') { should match(/^printlastlog\s+yes$/i) }
  end
end

control 'ssh-set-idle-timeout' do
  impact 0.5
  title 'Set SSH Client Alive Interval'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.9'
  tag('pci-dss' => '8.2.8')
  tag nist: ['3.1.11', 'AC-12', 'AC-17(a)', 'AC-2(5)', 'CM-6(a)', 'SC-10']
  tag level_cis: '1'
  tag ssg: 'sshd_set_idle_timeout'
  describe command('sshd -T') do
    its('stdout') { should match(/^clientaliveinterval\s+600$/i) }
  end
end

control 'ssh-set-keepalive' do
  impact 0.5
  title 'Set SSH Client Alive Count Max'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.9'
  tag('pci-dss' => '8.2.8')
  tag nist: ['3.1.11', 'AC-12', 'AC-17(a)', 'AC-2(5)', 'CM-6(a)', 'SC-10']
  tag level_cis: '1'
  tag ssg: 'sshd_set_keepalive'
  describe command('sshd -T') do
    its('stdout') { should match(/^clientalivecountmax\s+0$/i) }
  end
end

control 'ssh-set-login-grace-time' do
  impact 0.5
  title 'Ensure SSH LoginGraceTime is configured'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.15'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'sshd_set_login_grace_time'
  describe command('sshd -T') do
    its('stdout') { should match(/^logingracetime\s+60$/i) }
  end
end

control 'ssh-set-loglevel-info' do
  impact 0.3
  title 'Set LogLevel to INFO'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'sshd_set_loglevel_info'
  describe command('sshd -T') do
    its('stdout') { should match(/^loglevel\s+(info|verbose)$/i) }
  end
end

control 'ssh-set-loglevel-verbose' do
  impact 0.5
  title 'Set SSH Daemon LogLevel to VERBOSE'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.16'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-17(1)', 'AC-17(a)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'sshd_set_loglevel_verbose'
  describe command('sshd -T') do
    its('stdout') { should match(/^loglevel\s+verbose$/i) }
  end
end

control 'ssh-set-max-auth-tries' do
  impact 0.5
  title 'Set SSH authentication attempt limit'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.18'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'sshd_set_max_auth_tries'
  describe command('sshd -T') do
    its('stdout') { should match(/^maxauthtries\s+5$/i) }
  end
end

control 'ssh-set-max-sessions' do
  impact 0.5
  title 'Set SSH MaxSessions limit'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.19'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'sshd_set_max_sessions'
  describe command('sshd -T') do
    its('stdout') { should match(/^maxsessions\s+10$/i) }
  end
end

control 'ssh-set-maxstartups' do
  impact 0.5
  title 'Ensure SSH MaxStartups is configured'
  tag domain: 'SSH'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '5.1.20'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'sshd_set_maxstartups'
  describe command('sshd -T') do
    its('stdout') { should match(/^maxstartups\s+10:30:60$/i) }
  end
end
