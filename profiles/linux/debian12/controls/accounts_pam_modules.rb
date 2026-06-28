# Rendered from pavois reference (pavois-content/debian12.yml). Do not edit by hand.

control 'pam-faillock-audit' do
  impact 0.5
  title 'Account Lockouts Must Be Logged'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag nist: 'AC-7 (a)'
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

control 'pam-faillock-enabled' do
  impact 0.5
  title 'Ensure pam_faillock module is enabled'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.2.2'
  tag level_cis: '1'
  tag ssg: 'accounts_passwords_pam_faillock_enabled'
  describe command('grep -rqE \'^[^#]*\bpam_faillock\\.so\b\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-pwhistory-enabled' do
  impact 0.5
  title 'Verify pam_pwhistory module is activated'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.2.4'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_pwhistory_enabled'
  describe command('grep -rqE \'^[^#]*\bpam_pwhistory\\.so\b\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-pwhistory-enforce' do
  impact 0.5
  title 'Limit Password Reuse'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.3.2'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_pwhistory_enforce_root'
  describe command('grep -rqE \'^[^#]*\bpam_pwhistory\\.so\b[^#]*\benforce_for_root\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-pwhistory-use-authtok' do
  impact 0.5
  title 'Enforce Password History with use_authtok'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.3.3'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_pwhistory_use_authtok'
  describe command('grep -rqE \'^[^#]*\bpam_pwhistory\\.so\b[^#]*\buse_authtok\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-pwquality-enabled' do
  impact 0.5
  title 'Verify pam_pwquality module is activated'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.2.3'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_pwquality_enabled'
  describe command('grep -rqE \'^[^#]*\bpam_pwquality\\.so\b\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-unix-authtok' do
  impact 0.5
  title 'Require use_authtok for pam_unix.so'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.4.4'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_unix_authtok'
  describe command('grep -rqE \'^[^#]*\bpam_unix\\.so\b[^#]*\buse_authtok\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-unix-enabled' do
  impact 0.5
  title 'Verify pam_unix module is activated'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.2.1'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_unix_enabled'
  describe command('grep -rqE \'^[^#]*\bpam_unix\\.so\b\' /etc/pam.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pam-unix-no-nullok' do
  impact 0.7
  title 'Disallow Empty Passwords in pam_unix (no nullok)'
  tag domain: 'Accounts (PAM modules)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.4.1'
  tag level_cis: ['1', '2']
  tag ssg: 'no_empty_passwords_unix'
  describe command('grep -rqE \'^[^#]*\bpam_unix\\.so\b[^#]*\bnullok\' /etc/pam.d/ 2>/dev/null && echo ko || echo ok') do
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
