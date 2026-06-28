# Rendered from pavois reference (pavois-content/ubuntu2204.yml). Do not edit by hand.

control 'faillock-deny' do
  impact 0.5
  title 'Lock Accounts After Failed Password Attempts'
  tag domain: 'Accounts (faillock)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag cis: '5.3.3.1.1'
  tag('pci-dss' => '8.3.4')
  tag nist: ['3.1.8', 'AC-7(a)', 'CM-6(a)']
  tag stig: 'UBTU-22-411045'
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'accounts_passwords_pam_faillock_deny'
  describe command('v=$(grep -rh \'^[[:space:]]*deny[[:space:]]*=\' /etc/security/faillock.conf /etc/security/faillock.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[0-9]+\'); { [ -n "$v" ] && [ "$v" -le 3 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'faillock-unlock_time' do
  impact 0.5
  title 'Set Lockout Time for Failed Password Attempts'
  tag domain: 'Accounts (faillock)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag cis: '5.3.3.1.2'
  tag('pci-dss' => '8.3.4')
  tag nist: ['3.1.8', 'AC-7(b)', 'CM-6(a)']
  tag stig: 'UBTU-22-411045'
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'accounts_passwords_pam_faillock_unlock_time'
  describe command('v=$(grep -rh \'^[[:space:]]*unlock_time[[:space:]]*=\' /etc/security/faillock.conf /etc/security/faillock.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[0-9]+\'); { [ -n "$v" ] && [ "$v" -ge 900 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
