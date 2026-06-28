# Rendered from pavois reference (pavois-content/debian13.yml). Do not edit by hand.

control 'account-accounts-no-uid-except-zero' do
  impact 1.0
  title 'Verify Only Root Has UID 0'
  tag domain: 'Accounts'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.4.2.1'
  tag('pci-dss' => '8.2.1')
  tag nist: ['3.1.1', 'AC-6(5)', 'IA-2', 'IA-4(b)']
  tag level_cis: '1'
  tag ssg: 'accounts_no_uid_except_zero'
  describe command('awk -F: \'($3==0 && $1!="root"){print $1}\' /etc/passwd') do
    its('stdout.strip') { should eq '' }
  end
end

control 'account-accounts-password-all-shadowed' do
  impact 1.0
  title 'Verify All Account Password Hashes are Shadowed'
  tag domain: 'Accounts'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.2.1'
  tag('pci-dss' => '8.3.2')
  tag nist: ['3.5.10', 'CM-6(a)', 'IA-5(h)']
  tag level_cis: '1'
  tag ssg: 'accounts_password_all_shadowed'
  describe command('awk -F: \'($2!="x" && $2!="*" && $2!="!"){print $1}\' /etc/passwd') do
    its('stdout.strip') { should eq '' }
  end
end

control 'account-accounts-root-gid-zero' do
  impact 0.7
  title 'Verify Root Has A Primary GID 0'
  tag domain: 'Accounts'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '5.4.2.2'
  tag('pci-dss' => '8.2.1')
  tag level_cis: '1'
  tag ssg: 'accounts_root_gid_zero'
  describe command('awk -F: \'($1=="root" && $4!=0){print}\' /etc/passwd') do
    its('stdout.strip') { should eq '' }
  end
end

control 'account-gid-passwd-group-same' do
  impact 0.3
  title 'All GIDs referenced in /etc/passwd must be defined in /etc/group'
  tag domain: 'Accounts'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.2.3'
  tag('pci-dss' => '8.2.2')
  tag nist: ['CM-6(a)', 'IA-2']
  tag level_cis: '1'
  tag ssg: 'gid_passwd_group_same'
  describe command('awk -F: \'{print $4}\' /etc/passwd | sort -u | while read g; do getent group "$g" >/dev/null || echo "$g"; done') do
    its('stdout.strip') { should eq '' }
  end
end

control 'account-no-empty-passwords' do
  impact 1.0
  title 'Prevent Login to Accounts With Empty Password'
  tag domain: 'Accounts'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: ['5.3.3.4.1', '7.2.2']
  tag('pci-dss' => ['8.3.1', '2.2.2'])
  tag nist: ['3.1.1', 'CM-6(a)', 'IA-5(1)(a)', 'IA-5(c)']
  tag level_cis: '1'
  tag ssg: 'no_empty_passwords'
  describe command('awk -F: \'($2==""){print $1}\' /etc/shadow') do
    its('stdout.strip') { should eq '' }
  end
end
