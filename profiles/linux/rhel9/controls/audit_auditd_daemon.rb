# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'auditd-action-mail-acct' do
  impact 0.5
  title 'Configure auditd mail_acct Action on Low Disk Space'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.2.4'
  tag nist: ['3.3.1', 'AU-5(2)', 'AU-5(a)', 'CM-6(a)', 'IA-5(1)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_retention_action_mail_acct'
  describe command('grep -qiE \'^[[:space:]]*action_mail_acct[[:space:]]*=[[:space:]]*(root)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-admin-space-left-action' do
  impact 0.5
  title 'Configure auditd admin_space_left Action on Low Disk Space'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.2.4'
  tag('pci-dss' => '10.5.1')
  tag nist: ['3.3.1', 'AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_retention_admin_space_left_action'
  describe command('grep -qiE \'^[[:space:]]*admin_space_left_action[[:space:]]*=[[:space:]]*(single|halt)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-admin-space-left-percentage' do
  impact 0.5
  title 'Configure auditd admin_space_left on Low Disk Space'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'auditd_data_retention_admin_space_left_percentage'
  describe command('v=$(grep -iE \'^[[:space:]]*admin_space_left_percentage[[:space:]]*=\' /etc/audit/auditd.conf 2>/dev/null | grep -oE \'[0-9]+\' | tail -1); { [ -n "$v" ] && [ "$v" -ge 5 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-disk-error-action' do
  impact 0.5
  title 'Configure auditd Disk Error Action on Disk Error'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.2.3'
  tag nist: ['AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_disk_error_action_stig'
  describe command('grep -qiE \'^[[:space:]]*disk_error_action[[:space:]]*=[[:space:]]*(syslog|single|halt)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-disk-full-action' do
  impact 0.5
  title 'Configure auditd Disk Full Action when Disk Space Is Full'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.2.3'
  tag nist: ['AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_disk_full_action_stig'
  describe command('grep -qiE \'^[[:space:]]*disk_full_action[[:space:]]*=[[:space:]]*(halt|single)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-flush' do
  impact 0.5
  title 'Configure auditd flush priority'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag nist: '3.3.1'
  tag ssg: 'auditd_data_retention_flush'
  describe command('grep -qiE \'^[[:space:]]*flush[[:space:]]*=[[:space:]]*(incremental_async)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-freq' do
  impact 0.5
  title 'Set number of records to cause an explicit flush to audit logs'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'auditd_freq'
  describe command('v=$(grep -iE \'^[[:space:]]*freq[[:space:]]*=\' /etc/audit/auditd.conf 2>/dev/null | grep -oE \'[0-9]+\' | tail -1); { [ -n "$v" ] && [ "$v" -ge 100 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-max-log-file' do
  impact 0.5
  title 'Configure auditd Max Log File Size'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.2.1'
  tag nist: ['AU-11', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_retention_max_log_file'
  describe command('v=$(grep -iE \'^[[:space:]]*max_log_file[[:space:]]*=\' /etc/audit/auditd.conf 2>/dev/null | grep -oE \'[0-9]+\' | tail -1); { [ -n "$v" ] && [ "$v" -ge 6 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-max-log-file-action' do
  impact 0.5
  title 'Configure auditd max_log_file_action Upon Reaching Maximum Log Size'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.2.2'
  tag nist: ['AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_retention_max_log_file_action_stig'
  describe command('grep -qiE \'^[[:space:]]*max_log_file_action[[:space:]]*=[[:space:]]*(keep_logs)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-name-format' do
  impact 0.5
  title 'Set type of computer node name logging in audit logs'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag('pci-dss' => '10.2.2')
  tag ssg: 'auditd_name_format'
  describe command('grep -qiE \'^[[:space:]]*name_format[[:space:]]*=[[:space:]]*(hostname|fqd|numeric)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-space-left-action' do
  impact 0.5
  title 'Configure auditd space_left Action on Low Disk Space'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.2.4'
  tag('pci-dss' => '10.5.1')
  tag nist: ['3.3.1', 'AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_retention_space_left_action'
  describe command('grep -qiE \'^[[:space:]]*space_left_action[[:space:]]*=[[:space:]]*(email|exec|single|halt)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-space-left-percentage' do
  impact 0.5
  title 'Configure auditd space_left on Low Disk Space'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'auditd_data_retention_space_left_percentage'
  describe command('v=$(grep -iE \'^[[:space:]]*space_left_percentage[[:space:]]*=\' /etc/audit/auditd.conf 2>/dev/null | grep -oE \'[0-9]+\' | tail -1); { [ -n "$v" ] && [ "$v" -ge 25 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
