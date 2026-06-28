# Rendered from pavois reference (pavois-content/rhel8.yml). Do not edit by hand.

control 'findloop-dir-perms-world-writable-sticky-bits' do
  impact 0.5
  title 'Verify that All World-Writable Directories Have Sticky Bits Set'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R54'
  tag cis: '7.1.11'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'dir_perms_world_writable_sticky_bits'
  describe command('timeout 90 find / -xdev -type d -perm -0002 ! -perm -1000 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-dir-system-commands' do
  impact 0.5
  title 'Verify that system commands directories have root as a group owner'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag nist: ['CM-5(6)', 'CM-5(6).1']
  tag level_bp28: 'intermediary'
  tag ssg: 'dir_system_commands_group_root_owned'
  describe command('timeout 90 find /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin -type d ! -user root 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-file-groupowner-var-log' do
  impact 0.5
  title 'Verify Group Who Owns /var/log Directory'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R71'
  tag cis: '6.2.3.1'
  tag('pci-dss' => '10.3.2')
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_var_log'
  describe command('timeout 90 find /var/log -type f ! -group root ! -group adm ! -group syslog 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-file-groupownership-system-commands-dirs' do
  impact 0.5
  title 'Verify that system commands files are group owned by root or a system account'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag nist: ['CM-5(6)', 'CM-5(6).1']
  tag level_bp28: 'intermediary'
  tag ssg: 'file_groupownership_system_commands_dirs'
  describe command('timeout 90 find /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin -type f ! -group root 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-file-owner-var-log' do
  impact 0.5
  title 'Verify User Who Owns /var/log Directory'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R71'
  tag cis: '6.2.3.1'
  tag('pci-dss' => '10.3.2')
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_owner_var_log'
  describe command('timeout 90 find /var/log -type f ! -user root ! -user syslog 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-file-ownership-binary-dirs' do
  impact 0.5
  title 'Verify that System Executables Have Root Ownership'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag nist: ['AC-6(1)', 'CM-5(6)', 'CM-5(6).1', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag ssg: 'file_ownership_binary_dirs'
  describe command('timeout 90 find /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin -type f ! -user root 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-file-permissions-unauthorized-world-writable' do
  impact 0.5
  title 'Ensure No World-Writable Files Exist'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R54'
  tag cis: '7.1.11'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'file_permissions_unauthorized_world_writable'
  describe command('timeout 90 find / -xdev -type f -perm -0002 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-file-permissions-ungroupowned' do
  impact 0.5
  title 'Ensure All Files Are Owned by a Group'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R53'
  tag cis: '7.1.12'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'file_permissions_ungroupowned'
  describe command('timeout 90 find / -xdev -nogroup 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-file-permissions-var-log' do
  impact 0.5
  title 'Verify Permissions on /var/log Directory'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R71'
  tag cis: '6.2.3.1'
  tag('pci-dss' => '10.3.1')
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_permissions_var_log'
  describe command('timeout 90 find /var/log -type f -perm /037 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end

control 'findloop-no-files-unowned-by-user' do
  impact 0.5
  title 'Ensure All Files Are Owned by a User'
  tag domain: 'Filesystem (scan)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R53'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'minimal'
  tag ssg: 'no_files_unowned_by_user'
  describe command('timeout 90 find / -xdev -type f -nouser 2>/dev/null') do
    its('stdout.strip') { should eq '' }
  end
end
