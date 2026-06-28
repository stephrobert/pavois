# Rendered from pavois reference (pavois-content/fedora.yml). Do not edit by hand.

control 'sudo-remove-no-authenticate' do
  impact 0.5
  title 'Ensure Users Re-Authenticate for Privilege Escalation - sudo !authenticate'
  tag domain: 'Sudo'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.2.5'
  tag('pci-dss' => '2.2.6')
  tag nist: ['IA-11', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'sudo_remove_no_authenticate'
  describe command('grep -rqE \'^[^#]*!authenticate\' /etc/sudoers /etc/sudoers.d/ 2>/dev/null && echo ko || echo ok') do
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
