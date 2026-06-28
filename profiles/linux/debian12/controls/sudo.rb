# Rendered from pavois reference (pavois-content/debian12.yml). Do not edit by hand.

control 'sudo-custom-logfile' do
  impact 0.3
  title 'Ensure Sudo Logfile Exists - sudo logfile'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.2.3'
  tag('pci-dss' => '2.2.6')
  tag level_cis: ['1', '2']
  tag ssg: 'sudo_custom_logfile'
  describe command('grep -rqE \'^[^#]*Defaults[^#]*\blogfile\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-env-reset' do
  impact 0.5
  title 'Ensure sudo Runs In A Minimal Environment - sudo env_reset'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R39'
  tag level_bp28: 'intermediary'
  tag ssg: 'sudo_add_env_reset'
  describe command('grep -rqE \'^[^#]*Defaults[^#]*\benv_reset\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-ignore-dot' do
  impact 0.5
  title 'Ensure sudo Ignores Commands In Current Dir - sudo ignore_dot'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R39'
  tag level_bp28: 'intermediary'
  tag ssg: 'sudo_add_ignore_dot'
  describe command('grep -rqE \'^[^#]*Defaults[^#]*\bignore_dot\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-noexec' do
  impact 0.7
  title 'Ensure Privileged Escalated Commands Cannot Execute Other Commands - sudo NOEXEC'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R39'
  tag level_bp28: 'intermediary'
  tag ssg: 'sudo_add_noexec'
  describe command('grep -rqE \'^[^#]*Defaults[^#]*\bnoexec\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-remove-no-authenticate' do
  impact 0.5
  title 'Ensure Users Re-Authenticate for Privilege Escalation - sudo !authenticate'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.2.5'
  tag('pci-dss' => '2.2.6')
  tag nist: ['IA-11', 'CM-6(a)']
  tag level_cis: ['1', '2']
  tag ssg: 'sudo_remove_no_authenticate'
  describe command('grep -rqE \'^[^#]*!authenticate\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ko || echo ok') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-require-authentication' do
  impact 0.5
  title 'Ensure Users Re-Authenticate for Privilege Escalation - sudo NOPASSWD'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.2.4'
  tag('pci-dss' => '2.2.6')
  tag nist: ['IA-11', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'sudo_require_authentication'
  describe command('grep -rqE \'^[^#]*\bNOPASSWD\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ko || echo ok') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-require-reauthentication' do
  impact 0.5
  title 'Require Re-Authentication When Using the sudo Command - timestamp_timeout'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.2.6'
  tag('pci-dss' => '2.2.6')
  tag nist: 'IA-11'
  tag level_cis: ['1', '2']
  tag ssg: 'sudo_require_reauthentication'
  describe command('grep -rqE \'timestamp_timeout[[:space:]]*=[[:space:]]*-1\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ko || echo ok') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-requiretty' do
  impact 0.5
  title 'Ensure Only Users Logged In To Real tty Can Execute Sudo - sudo requiretty'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R39'
  tag level_bp28: 'intermediary'
  tag ssg: 'sudo_add_requiretty'
  describe command('grep -rqE \'^[^#]*Defaults[^#]*\brequiretty\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-umask' do
  impact 0.5
  title 'Ensure sudo umask is appropriate - sudo umask'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R39'
  tag level_bp28: 'intermediary'
  tag ssg: 'sudo_add_umask'
  describe command('grep -rqE \'^[^#]*Defaults[^#]*\bumask\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'sudo-use-pty' do
  impact 0.5
  title 'Ensure Only Users Logged In To Real tty Can Execute Sudo - sudo use_pty'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R39'
  tag cis: ['2.2.6', '5.2.2']
  tag('pci-dss' => '2.2.6')
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sudo_add_use_pty'
  describe command('grep -rqE \'^[^#]*Defaults[^#]*\buse_pty\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
