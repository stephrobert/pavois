# Rendered from pavois reference (pavois-content/ubuntu2404.yml). Do not edit by hand.

control 'auditd-action-mail-acct' do
  impact 0.5
  title 'Configure auditd mail_acct Action on Low Disk Space'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.2.2.4'
  tag nist: ['3.3.1', 'AU-5(2)', 'AU-5(a)', 'CM-6(a)', 'IA-5(1)']
  tag stig: 'UBTU-24-900980'
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
  tag cis: ['10.5.1', '6.2.2.4']
  tag('pci-dss' => 'Req-10.7')
  tag nist: ['3.3.1', 'AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_retention_admin_space_left_action'
  describe command('grep -qiE \'^[[:space:]]*admin_space_left_action[[:space:]]*=[[:space:]]*(halt)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-disk-error-action' do
  impact 0.5
  title 'Configure auditd Disk Error Action on Disk Error'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.2.2.3'
  tag nist: ['AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_disk_error_action'
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
  tag cis: '6.2.2.3'
  tag nist: ['AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_disk_full_action'
  describe command('grep -qiE \'^[[:space:]]*disk_full_action[[:space:]]*=[[:space:]]*(halt|single)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-max-log-file' do
  impact 0.5
  title 'Configure auditd Max Log File Size'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.2.2.1'
  tag('pci-dss' => 'Req-10.7')
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
  tag cis: '6.2.2.2'
  tag('pci-dss' => 'Req-10.7')
  tag nist: ['AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'auditd_data_retention_max_log_file_action'
  describe command('grep -qiE \'^[[:space:]]*max_log_file_action[[:space:]]*=[[:space:]]*(keep_logs)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-space-left-action' do
  impact 0.5
  title 'Configure auditd space_left Action on Low Disk Space'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: ['10.5.1', '6.2.2.4']
  tag('pci-dss' => 'Req-10.7')
  tag nist: ['3.3.1', 'AU-5(1)', 'AU-5(2)', 'AU-5(4)', 'AU-5(b)', 'CM-6(a)']
  tag stig: 'UBTU-24-900960'
  tag level_cis: '2'
  tag ssg: 'auditd_data_retention_space_left_action'
  describe command('grep -qiE \'^[[:space:]]*space_left_action[[:space:]]*=[[:space:]]*(email)\b\' /etc/audit/auditd.conf 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'auditd-space-left-percentage' do
  impact 0.5
  title 'Configure auditd space_left on Low Disk Space'
  tag domain: 'Audit (auditd daemon)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag('pci-dss' => 'Req-10.7')
  tag nist: ['AU-5(b)', 'AU-5(2)', 'AU-5(1)', 'AU-5(4)', 'CM-6(a)']
  tag stig: 'UBTU-24-900960'
  tag ssg: 'auditd_data_retention_space_left_percentage'
  describe command('v=$(grep -iE \'^[[:space:]]*space_left_percentage[[:space:]]*=\' /etc/audit/auditd.conf 2>/dev/null | grep -oE \'[0-9]+\' | tail -1); { [ -n "$v" ] && [ "$v" -ge 25 ] && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
