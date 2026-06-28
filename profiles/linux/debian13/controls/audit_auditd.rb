# Rendered from pavois reference (pavois-content/debian13.yml). Do not edit by hand.

control 'audit-dac-modification' do
  impact 0.5
  title 'Record Events that Modify the System\'s Discretionary Access Controls - chmod'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag('pci-dss' => '10.3.4')
  tag nist: ['3.1.7', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_dac_modification_chmod'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)perm_mod\b/) }
  end
  describe command("grep -rhwsF 'perm_mod' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-execution-chacl' do
  impact 0.5
  title 'Record Any Attempts to Run chacl'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: ['R73', 'R33']
  tag cis: ['6.3.3.17', '6.3.3.15', '6.3.3.16', '6.3.3.18']
  tag nist: '3.1.7'
  tag level_bp28: ['enhanced', 'intermediary']
  tag level_cis: '2'
  tag ssg: 'audit_rules_execution_chacl'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)privileged\b/) }
  end
  describe command("grep -rhwsF 'privileged' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-file-deletion-events' do
  impact 0.5
  title 'Ensure auditd Collects File Deletion Events by User - rename'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag('pci-dss' => '10.2.1.7')
  tag nist: ['3.1.7', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_file_deletion_events_rename'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)delete\b/) }
  end
  describe command("grep -rhwsF 'delete' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-immutable' do
  impact 0.5
  title 'Make the auditd Configuration Immutable'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R73'
  tag('pci-dss' => '10.3.2')
  tag nist: ['3.3.1', 'AC-6(9)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_immutable'
  describe command('auditctl -s') do
    its('stdout') { should match(/enabled[[:space:]]+2/) }
  end
end

control 'audit-login-events' do
  impact 0.5
  title 'Record Attempts to Alter Logon and Logout Events - faillock'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag('pci-dss' => '10.2.1.3')
  tag nist: ['3.1.7', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_login_events_faillock'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)logins\b/) }
  end
  describe command("grep -rhwsF 'logins' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-mac-modification' do
  impact 0.5
  title 'Record Events that Modify the System\'s Mandatory Access Controls'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: '6.3.3.14'
  tag('pci-dss' => '10.3.4')
  tag nist: ['3.1.8', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'audit_rules_mac_modification'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)MAC\-policy\b/) }
  end
  describe command("grep -rhwsF 'MAC-policy' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-media-export' do
  impact 0.5
  title 'Ensure auditd Collects Information on Exporting to Media (successful)'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag('pci-dss' => '10.2.1.7')
  tag nist: ['3.1.7', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_media_export'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)export\b/) }
  end
  describe command("grep -rhwsF 'export' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-networkconfig-modification' do
  impact 0.5
  title 'Record Events that Modify the System\'s Network Environment'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '6.3.3.5'
  tag nist: ['3.1.7', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'audit_rules_networkconfig_modification'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)(audit_rules_networkconfig_modification|system-locale)\b/) }
  end
  describe command("grep -rhwsF '(audit_rules_networkconfig_modification|system-locale)' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-privileged-commands-rmmod' do
  impact 0.5
  title 'Ensure auditd Collects Information on the Use of Privileged Commands - rmmod'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: '6.3.3.19'
  tag nist: '3.1.7'
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'audit_rules_privileged_commands_rmmod'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)modules\b/) }
  end
  describe command("grep -rhwsF 'modules' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-session-events' do
  impact 0.5
  title 'Record Attempts to Alter Process and Session Initiation Information btmp'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag('pci-dss' => '10.2.1.3')
  tag nist: ['3.1.7', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_session_events_btmp'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)session\b/) }
  end
  describe command("grep -rhwsF 'session' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-suid-auid-privilege-function' do
  impact 0.5
  title 'Record Events When Executables Are Run As Another User'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '6.3.3.2'
  tag level_cis: '2'
  tag ssg: 'audit_rules_suid_auid_privilege_function'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)user_emulation\b/) }
  end
  describe command("grep -rhwsF 'user_emulation' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-sysadmin-actions' do
  impact 0.5
  title 'Ensure auditd Collects System Administrator Actions'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag('pci-dss' => '10.2.1.5')
  tag nist: ['3.1.7', 'AC-2(7)(b)', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_sysadmin_actions'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)actions\b/) }
  end
  describe command("grep -rhwsF 'actions' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-time' do
  impact 0.5
  title 'Record attempts to alter time through adjtimex'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: '6.3.3.4'
  tag('pci-dss' => '10.6.3')
  tag nist: ['3.1.7', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'audit_rules_time_adjtimex'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)audit_time_rules\b/) }
  end
  describe command("grep -rhwsF 'audit_time_rules' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-time-clock-settime' do
  impact 0.5
  title 'Record Attempts to Alter Time Through clock_settime'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag('pci-dss' => '10.6.3')
  tag nist: ['3.1.7', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_time_clock_settime'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)time\-change\b/) }
  end
  describe command("grep -rhwsF 'time-change' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-unsuccessful-file-modification' do
  impact 0.5
  title 'Record Unsuccessful Access Attempts to Files - creat'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag nist: ['3.1.7', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag ssg: 'audit_rules_unsuccessful_file_modification_creat'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)access\b/) }
  end
  describe command("grep -rhwsF 'access' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-usergroup-modification' do
  impact 0.5
  title 'Record Events that Modify User/Group Information - /etc/group'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: '6.3.3.8'
  tag('pci-dss' => '10.2.1.5')
  tag nist: ['3.1.7', 'AC-2(4)', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'audit_rules_usergroup_modification_group'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)audit_rules_usergroup_modification\b/) }
  end
  describe command("grep -rhwsF 'audit_rules_usergroup_modification' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end
