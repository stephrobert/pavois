# Rendered from pavois reference (pavois-content/ubuntu2404.yml). Do not edit by hand.

control 'audit-dac-modification' do
  impact 0.5
  title 'Record Events that Modify the System\'s Discretionary Access Controls - chmod'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: ['10.3.4', '6.2.3.9']
  tag('pci-dss' => '10.3.4')
  tag nist: ['3.1.7', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag stig: ['UBTU-24-900150', 'UBTU-24-900140', 'UBTU-24-900130']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'audit_rules_dac_modification_chmod'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)perm_mod\b/) }
  end
  describe command("grep -rhwsF 'perm_mod' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-etc-cron-d' do
  impact 0.5
  title 'Ensure auditd Collects Changes to Cron Jobs - /etc/cron.d/'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag stig: 'UBTU-24-200270'
  tag ssg: 'audit_rules_etc_cron_d'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)cronjobs\b/) }
  end
  describe command("grep -rhwsF 'cronjobs' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
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
  tag cis: '6.2.3.17'
  tag nist: '3.1.7'
  tag stig: ['UBTU-24-900240', 'UBTU-24-900210', 'UBTU-24-900230', 'UBTU-24-900220', 'UBTU-24-900300', 'UBTU-24-900080', 'UBTU-24-900190', 'UBTU-24-900320', 'UBTU-24-900290', 'UBTU-24-900740', 'UBTU-24-900090', 'UBTU-24-900200', 'UBTU-24-900330', 'UBTU-24-900270', 'UBTU-24-900110', 'UBTU-24-900120', 'UBTU-24-900070', 'UBTU-24-900170', 'UBTU-24-900180', 'UBTU-24-900100', 'UBTU-24-900280', 'UBTU-24-900310']
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
  tag cis: ['10.2.1.7', '6.2.3.13']
  tag('pci-dss' => '10.2.1.7')
  tag nist: ['3.1.7', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag stig: 'UBTU-24-900540'
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
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
  tag cis: ['10.3.2', '6.2.3.20']
  tag('pci-dss' => '10.3.2')
  tag nist: ['3.3.1', 'AC-6(9)', 'CM-6(a)']
  tag stig: 'UBTU-24-909000'
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
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
  tag cis: ['10.2.1.3', '6.2.3.12']
  tag('pci-dss' => '10.2.1.3')
  tag nist: ['3.1.7', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag stig: ['UBTU-24-900250', 'UBTU-24-900260']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
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
  tag cis: ['6.2.3.14', '6.3.3.14']
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
  tag cis: ['10.2.1.7', '6.2.3.10']
  tag('pci-dss' => '10.2.1.7')
  tag nist: ['3.1.7', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
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
  tag cis: ['10.3.4', '6.2.3.5']
  tag('pci-dss' => '10.3.4')
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

control 'audit-privileged-commands-fdisk' do
  impact 0.5
  title 'Ensure auditd Collects Information on the Use of Privileged Commands - fdisk'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: '6.2.3.19'
  tag nist: '3.1.7'
  tag stig: ['UBTU-24-900350', 'UBTU-24-900340', 'UBTU-24-900750', 'UBTU-24-900730']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'audit_rules_privileged_commands_fdisk'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)modules\b/) }
  end
  describe command("grep -rhwsF 'modules' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-session-events' do
  impact 0.5
  title 'Record Attempts to Alter Process and Session Initiation Information'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: '6.2.3.11'
  tag('pci-dss' => '10.2.1.3')
  tag nist: ['3.1.7', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag stig: ['UBTU-24-900610', 'UBTU-24-900600', 'UBTU-24-900590']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'audit_rules_session_events'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)session\b/) }
  end
  describe command("grep -rhwsF 'session' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-sudoers' do
  impact 0.5
  title 'Ensure auditd Collects System Administrator Actions - /etc/sudoers'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: '6.2.3.1'
  tag('pci-dss' => '10.2.1.5')
  tag nist: '3.1.7'
  tag stig: ['UBTU-24-900510', 'UBTU-24-900520']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'audit_rules_sudoers'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)actions\b/) }
  end
  describe command("grep -rhwsF 'actions' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-suid-auid-privilege-function' do
  impact 0.5
  title 'Record Events When Executables Are Run As Another User'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '6.2.3.2'
  tag level_cis: '2'
  tag ssg: 'audit_rules_suid_auid_privilege_function'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)user_emulation\b/) }
  end
  describe command("grep -rhwsF 'user_emulation' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'audit-suid-privilege-function' do
  impact 0.5
  title 'Record Events When Privileged Executables Are Run'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '10.2.1.2'
  tag('pci-dss' => '10.2.1.2')
  tag nist: ['AC-6(9)', 'AU-12(3)', 'AU-7(a)', 'AU-7(b)', 'AU-8(b)', 'CM-5(1)']
  tag stig: 'UBTU-24-200580'
  tag ssg: 'audit_rules_suid_privilege_function'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)execpriv\b/) }
  end
end

control 'audit-time' do
  impact 0.5
  title 'Record attempts to alter time through adjtimex'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R73'
  tag cis: ['10.6.3', '6.2.3.4']
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
  tag cis: ['10.6.3', '6.2.3.4']
  tag('pci-dss' => '10.6.3')
  tag nist: ['3.1.7', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
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
  tag cis: '6.2.3.7'
  tag('pci-dss' => ['Req-10.2.1', '10.2.1.4'])
  tag nist: ['3.1.7', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag stig: 'UBTU-24-900160'
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
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
  tag cis: ['10.2.1.5', '6.2.3.8']
  tag('pci-dss' => '10.2.1.5')
  tag nist: ['3.1.7', 'AC-2(4)', 'AC-6(9)', 'AU-12(c)', 'AU-2(d)', 'CM-6(a)']
  tag stig: ['UBTU-24-200290', 'UBTU-24-200310', 'UBTU-24-200320', 'UBTU-24-200280', 'UBTU-24-200300']
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

control 'audit-var-log-journal' do
  impact 0.5
  title 'Ensure auditd Collects records for events that affect "/var/log/journal"'
  tag domain: 'Audit (auditd)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag stig: 'UBTU-24-300029'
  tag ssg: 'audit_rules_var_log_journal'
  describe command('auditctl -l') do
    its('stdout') { should match(/(-k +|key=)systemd_journal\b/) }
  end
  describe command("grep -rhwsF 'systemd_journal' /etc/audit/rules.d/*.rules /etc/audit/audit.rules 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end
