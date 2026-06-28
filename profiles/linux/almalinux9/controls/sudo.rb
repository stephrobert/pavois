# Rendered from pavois reference (pavois-content/almalinux9.yml). Do not edit by hand.

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

control 'sudo-require-authentication' do
  impact 0.5
  title 'Ensure Users Re-Authenticate for Privilege Escalation - sudo'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.2.4'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '2'
  tag ssg: 'sudo_require_authentication'
  describe command('grep -rqE \'^[^#]*!authenticate\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ko || echo ok') do
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

control 'sudo-use-pty' do
  impact 0.5
  title 'Ensure Only Users Logged In To Real tty Can Execute Sudo - sudo use_pty'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R39'
  tag cis: '5.2.2'
  tag('pci-dss' => '2.2.6')
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sudo_add_use_pty'
  describe command('grep -rqE \'^[^#]*Defaults[^#]*\buse_pty\b\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
