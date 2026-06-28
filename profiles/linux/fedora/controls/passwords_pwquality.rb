# Rendered from pavois reference (pavois-content/fedora.yml). Do not edit by hand.

control 'pwquality-dcredit' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Minimum Digit Characters'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag('pci-dss' => '8.3.6')
  tag nist: ['CM-6(a)', 'IA-5(1)(a)', 'IA-5(4)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag ssg: 'accounts_password_pam_dcredit'
  describe command('v=$(grep -rh \'^[[:space:]]*dcredit[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -le -1 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-dictcheck' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Prevent the Use of Dictionary Words'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.2.6'
  tag nist: ['CM-6(a)', 'IA-5(1)(a)', 'IA-5(4)', 'IA-5(c)']
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_dictcheck'
  describe command('v=$(grep -rh \'^[[:space:]]*dictcheck[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -ge 1 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-difok' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Minimum Different Characters'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.2.1'
  tag nist: ['CM-6(a)', 'IA-5(1)(b)', 'IA-5(4)', 'IA-5(c)']
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_difok'
  describe command('v=$(grep -rh \'^[[:space:]]*difok[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -ge 2 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-lcredit' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Minimum Lowercase Characters'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag('pci-dss' => '8.3.6')
  tag nist: ['CM-6(a)', 'IA-5(1)(a)', 'IA-5(4)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag ssg: 'accounts_password_pam_lcredit'
  describe command('v=$(grep -rh \'^[[:space:]]*lcredit[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -le -1 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-maxrepeat' do
  impact 0.5
  title 'Set Password Maximum Consecutive Repeating Characters'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.2.4'
  tag nist: ['CM-6(a)', 'IA-5(4)', 'IA-5(c)']
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_maxrepeat'
  describe command('v=$(grep -rh \'^[[:space:]]*maxrepeat[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -le 3 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-maxsequence' do
  impact 0.5
  title 'Limit the maximum number of sequential characters in passwords'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.3.3.2.5'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_maxsequence'
  describe command('v=$(grep -rh \'^[[:space:]]*maxsequence[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -le 3 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-minclass' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Minimum Different Categories'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R68'
  tag cis: '5.3.3.2.3'
  tag nist: ['CM-6(a)', 'IA-5(1)(a)', 'IA-5(4)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_minclass'
  describe command('v=$(grep -rh \'^[[:space:]]*minclass[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -ge 4 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-minlen' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Minimum Length'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag cis: '5.3.3.2.2'
  tag('pci-dss' => '8.3.6')
  tag nist: ['CM-6(a)', 'IA-5(1)(a)', 'IA-5(4)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'accounts_password_pam_minlen'
  describe command('v=$(grep -rh \'^[[:space:]]*minlen[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -ge 14 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-ocredit' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Minimum Special Characters'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag nist: ['CM-6(a)', 'IA-5(1)(a)', 'IA-5(4)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag ssg: 'accounts_password_pam_ocredit'
  describe command('v=$(grep -rh \'^[[:space:]]*ocredit[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -le -1 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-retry' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Authentication Retry Prompts Permitted Per-Session'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R68'
  tag nist: ['AC-7(a)', 'CM-6(a)', 'IA-5(4)']
  tag level_bp28: 'minimal'
  tag ssg: 'accounts_password_pam_retry'
  describe command('v=$(grep -rh \'^[[:space:]]*retry[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -le 3 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'pwquality-ucredit' do
  impact 0.5
  title 'Ensure PAM Enforces Password Requirements - Minimum Uppercase Characters'
  tag domain: 'Passwords (pwquality)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag nist: ['CM-6(a)', 'IA-5(1)(a)', 'IA-5(4)', 'IA-5(c)']
  tag level_bp28: 'minimal'
  tag ssg: 'accounts_password_pam_ucredit'
  describe command('v=$(grep -rh \'^[[:space:]]*ucredit[[:space:]]*=\' /etc/security/pwquality.conf /etc/security/pwquality.conf.d/ 2>/dev/null | tail -1 | grep -oE \'[-]?[0-9]+\'); { [ -n "$v" ] && [ "$v" -le -1 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
