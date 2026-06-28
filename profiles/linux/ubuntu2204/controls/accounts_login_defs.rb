# Rendered from pavois reference (pavois-content/ubuntu2204.yml). Do not edit by hand.

control 'logindefs-encrypt_method' do
  impact 0.5
  title 'Set Password Hashing Algorithm in /etc/login.defs'
  tag domain: 'Accounts (login.defs)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.4.1.4'
  tag('pci-dss' => '8.3.2')
  tag nist: ['3.13.11', 'CM-6(a)', 'IA-5(1)(c)', 'IA-5(c)']
  tag stig: 'UBTU-22-611070'
  tag level_cis: '1'
  tag ssg: 'set_password_hashing_algorithm_logindefs'
  describe login_defs do
    its('ENCRYPT_METHOD') { should cmp 'SHA512|YESCRYPT' }
  end
end

control 'logindefs-pass_max_days' do
  impact 0.5
  title 'Set Password Maximum Age'
  tag domain: 'Accounts (login.defs)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.4.1.1'
  tag('pci-dss' => '8.3.9')
  tag nist: ['3.5.6', 'CM-6(a)', 'IA-5(1)(d)', 'IA-5(f)']
  tag stig: 'UBTU-22-411030'
  tag level_cis: '1'
  tag ssg: 'accounts_maximum_age_login_defs'
  describe login_defs do
    its('PASS_MAX_DAYS') { should cmp <= 365 }
  end
end

control 'logindefs-pass_min_days' do
  impact 0.5
  title 'Set Password Minimum Age'
  tag domain: 'Accounts (login.defs)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.4.1.2'
  tag nist: ['3.5.8', 'CM-6(a)', 'IA-5(1)(d)', 'IA-5(f)']
  tag stig: 'UBTU-22-411025'
  tag level_cis: '2'
  tag ssg: 'accounts_minimum_age_login_defs'
  describe login_defs do
    its('PASS_MIN_DAYS') { should cmp >= 1 }
  end
end

control 'logindefs-pass_min_len' do
  impact 0.5
  title 'Minimum password length (per-standard threshold)'
  tag domain: 'Accounts (login.defs)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R31'
  tag nist: ['3.5.7', 'CM-6(a)', 'IA-5(1)(a)', 'IA-5(f)']
  tag level_bp28: 'minimal'
  tag merge_group: 'logindefs-pass_min_len'
  tag ssg: 'accounts_password_minlen_login_defs'
  describe login_defs do
    its('PASS_MIN_LEN') { should cmp >= {'bp28'=>15,'nist'=>12}.fetch(input('pavois_standard', value: '_default'), 15) }
  end
end

control 'logindefs-pass_warn_age' do
  impact 0.5
  title 'Set Password Warning Age'
  tag domain: 'Accounts (login.defs)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.4.1.3'
  tag('pci-dss' => '8.3.9')
  tag nist: ['3.5.8', 'CM-6(a)', 'IA-5(1)(d)', 'IA-5(f)']
  tag level_cis: '1'
  tag ssg: 'accounts_password_warn_age_login_defs'
  describe login_defs do
    its('PASS_WARN_AGE') { should cmp >= 7 }
  end
end
