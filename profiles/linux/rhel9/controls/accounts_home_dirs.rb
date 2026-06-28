# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'home-directory-exists' do
  impact 0.5
  title 'All Interactive Users Home Directories Must Exist'
  tag domain: 'Accounts (home dirs)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.2.8'
  tag level_cis: '1'
  tag ssg: 'accounts_user_interactive_home_directory_exists'
  describe command('awk -F: \'($3>=1000 && $3!=65534 && $6!="/"){print $3":"$4":"$6}\' /etc/passwd | while IFS=: read u g h; do [ -d "$h" ] || echo "$h"; done | head -1') do
    its('stdout.strip') { should eq '' }
  end
end

control 'home-dot-group-ownership' do
  impact 0.5
  title 'User Initialization Files Must Be Group-Owned By The Primary Group'
  tag domain: 'Accounts (home dirs)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.2.9'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'accounts_user_dot_group_ownership'
  describe command('awk -F: \'($3>=1000 && $3!=65534 && $6!="/"){print $3":"$4":"$6}\' /etc/passwd | while IFS=: read u g h; do [ -d "$h" ] && timeout 60 find -P "$h" -maxdepth 1 -type f -name \'.[^.]*\' ! -gid "$g" -print 2>/dev/null; done | head -1') do
    its('stdout.strip') { should eq '' }
  end
end

control 'home-dot-user-ownership' do
  impact 0.5
  title 'User Initialization Files Must Be Owned By the Primary User'
  tag domain: 'Accounts (home dirs)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.2.9'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'accounts_user_dot_user_ownership'
  describe command('awk -F: \'($3>=1000 && $3!=65534 && $6!="/"){print $3":"$4":"$6}\' /etc/passwd | while IFS=: read u g h; do [ -d "$h" ] && timeout 60 find -P "$h" -maxdepth 1 -type f -name \'.[^.]*\' ! -uid "$u" -print 2>/dev/null; done | head -1') do
    its('stdout.strip') { should eq '' }
  end
end

control 'home-files-groupownership' do
  impact 0.5
  title 'All User Files and Directories In The Home Directory Must Be Group-Owned By The Primary Group'
  tag domain: 'Accounts (home dirs)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'accounts_users_home_files_groupownership'
  describe command('awk -F: \'($3>=1000 && $3!=65534 && $6!="/"){print $3":"$4":"$6}\' /etc/passwd | while IFS=: read u g h; do [ -d "$h" ] && timeout 60 find -P "$h" ! -gid "$g" ! -type l -print 2>/dev/null; done | head -1') do
    its('stdout.strip') { should eq '' }
  end
end

control 'home-files-ownership' do
  impact 0.5
  title 'All User Files and Directories In The Home Directory Must Have a Valid Owner'
  tag domain: 'Accounts (home dirs)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'accounts_users_home_files_ownership'
  describe command('awk -F: \'($3>=1000 && $3!=65534 && $6!="/"){print $3":"$4":"$6}\' /etc/passwd | while IFS=: read u g h; do [ -d "$h" ] && timeout 60 find -P "$h" ! -uid "$u" ! -type l -print 2>/dev/null; done | head -1') do
    its('stdout.strip') { should eq '' }
  end
end

control 'home-files-permissions' do
  impact 0.5
  title 'All User Files and Directories In The Home Directory Must Have Mode 0750 Or Less Permissive'
  tag domain: 'Accounts (home dirs)'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'accounts_users_home_files_permissions'
  describe command('awk -F: \'($3>=1000 && $3!=65534 && $6!="/"){print $3":"$4":"$6}\' /etc/passwd | while IFS=: read u g h; do [ -d "$h" ] && timeout 60 find -P "$h" -perm /7027 ! -type l -print 2>/dev/null; done | head -1') do
    its('stdout.strip') { should eq '' }
  end
end
