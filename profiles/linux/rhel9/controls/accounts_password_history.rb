# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'pam-remember-pwhistory-remember' do
  impact 0.5
  title 'Limit Password Reuse: password-auth'
  tag domain: 'Accounts (password history)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.3.1'
  tag('pci-dss' => '8.3.7')
  tag nist: '3.5.8'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_pwhistory_remember_password_auth'
  describe command('v=$(grep -rhoE \'remember=[0-9]+\' /etc/pam.d/ /etc/security/pwhistory.conf 2>/dev/null | grep -oE \'[0-9]+\' | sort -n | tail -1); { [ -n "$v" ] && [ "$v" -ge 24 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-remember-unix-remember' do
  impact 0.5
  title 'Limit Password Reuse'
  tag domain: 'Accounts (password history)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag('pci-dss' => '8.3.7')
  tag nist: ['3.5.8', 'IA-5(1)(e)', 'IA-5(f)']
  tag level_bp28: 'minimal'
  tag ssg: 'accounts_password_pam_unix_remember'
  describe command('v=$(grep -rhoE \'remember=[0-9]+\' /etc/pam.d/ /etc/security/pwhistory.conf 2>/dev/null | grep -oE \'[0-9]+\' | sort -n | tail -1); { [ -n "$v" ] && [ "$v" -ge 2 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
