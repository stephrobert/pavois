# Rendered from pavois reference (pavois-content/ubuntu2204.yml). Do not edit by hand.

control 'umask-etc-bashrc' do
  impact 0.5
  title 'Ensure the Default Bash Umask is Set Correctly'
  tag domain: 'Accounts (umask)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R36'
  tag cis: '5.4.3.3'
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag stig: 'UBTU-22-412035'
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'accounts_umask_etc_bashrc'
  describe command('v=$(grep -hiE \'^[[:space:]]*umask[[:space:]]+[0-7]+\' /etc/bash.bashrc 2>/dev/null | grep -oE \'[0-7]+\' | tail -1); { [ -n "$v" ] && [ $((0$v & 0027)) -eq $((0027)) ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'umask-etc-login-defs' do
  impact 0.5
  title 'Ensure the Default Umask is Set Correctly in login.defs (077)'
  tag domain: 'Accounts (umask)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R36'
  tag cis: '5.4.3.3'
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag stig: 'UBTU-22-412035'
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag merge_group: 'umask-etc-login-defs'
  tag ssg: 'accounts_umask_etc_login_defs'
  m = {'bp28'=>'0077','cis'=>'0027'}.fetch(input('pavois_standard', value: '_default'), '0077')
  describe command("v=$(grep -hiE '^[[:space:]]*UMASK[[:space:]]+[0-7]+' /etc/login.defs 2>/dev/null | grep -oE '[0-7]+' | tail -1); { [ -n \"$v\" ] && [ $((0$v & #{m})) -eq $((#{m})) ] && echo ok; } || echo ko") do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'umask-etc-profile' do
  impact 0.5
  title 'Ensure the Default Umask is Set Correctly in /etc/profile'
  tag domain: 'Accounts (umask)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R36'
  tag cis: '5.4.3.3'
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag stig: 'UBTU-22-412035'
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'accounts_umask_etc_profile'
  describe command('v=$(grep -hiE \'^[[:space:]]*umask[[:space:]]+[0-7]+\' /etc/profile /etc/profile.d/*.sh 2>/dev/null | grep -oE \'[0-7]+\' | tail -1); { [ -n "$v" ] && [ $((0$v & 0027)) -eq $((0027)) ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
