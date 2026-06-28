# Rendered from pavois reference (pavois-content/almalinux9.yml). Do not edit by hand.

control 'pam-faillock-deny-root' do
  impact 0.5
  title 'Configure the root Account for Failed Password Attempts'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag cis: '5.3.3.1.3'
  tag nist: ['AC-7(b)', 'CM-6(a)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag level_cis: '2'
  tag ssg: 'accounts_passwords_pam_faillock_deny_root'
  describe command('grep -rqE \'^[^#]*\bpam_faillock\\.so\b[^#]*\beven_deny_root\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-unix-rounds-password-auth' do
  impact 0.5
  title 'Set number of Password Hashing Rounds - password-auth'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R68'
  tag level_bp28: 'minimal'
  tag ssg: 'accounts_password_pam_unix_rounds_password_auth'
  describe command('grep -rqE \'^[^#]*\bpam_unix\\.so\b[^#]*\brounds=[0-9]\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
