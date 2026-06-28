# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'pam-faillock-audit' do
  impact 0.5
  title 'Account Lockouts Must Be Logged'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'accounts_passwords_pam_faillock_audit'
  describe command('grep -rqE \'^[^#]*\bpam_faillock\\.so\b[^#]*\baudit\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-faillock-deny-root' do
  impact 0.5
  title 'Configure the root Account for Failed Password Attempts'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag nist: ['AC-7(b)', 'CM-6(a)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag ssg: 'accounts_passwords_pam_faillock_deny_root'
  describe command('grep -rqE \'^[^#]*\bpam_faillock\\.so\b[^#]*\beven_deny_root\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-pwhistory-enforce-for-root' do
  impact 0.5
  title 'Ensure Password History Is Enforced for the Root User'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.3.2'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_pwhistory_enforce_for_root'
  describe command('grep -rqE \'^[^#]*\bpam_pwhistory\\.so\b[^#]*\benforce_for_root\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-unix-no-remember' do
  impact 0.5
  title 'Avoid using remember in pam_unix module'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.4.2'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_unix_no_remember'
  describe command('grep -rE \'^[^#]*\bpam_unix\\.so\b\' /etc/pam.d/ 2>/dev/null | grep -q \'remember=\' && echo ko || echo ok') do
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
