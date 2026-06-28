# Rendered from pavois reference (pavois-content/ubuntu2204.yml). Do not edit by hand.

control 'journald-compress' do
  impact 0.5
  title 'Ensure journald is configured to compress large log files'
  tag domain: 'Logging (journald)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.2.1.1.6'
  tag level_cis: '1'
  tag ssg: 'journald_compress'
  describe command('grep -rqiE \'^[[:space:]]*Compress[[:space:]]*=[[:space:]]*yes\b\' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'journald-forwardtosyslog' do
  impact 0.5
  title 'Ensure journald ForwardToSyslog is disabled'
  tag domain: 'Logging (journald)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.2.1.1.4'
  tag level_cis: '1'
  tag ssg: 'journald_disable_forward_to_syslog'
  describe command('grep -rqiE \'^[[:space:]]*ForwardToSyslog[[:space:]]*=[[:space:]]*no\b\' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'journald-storage' do
  impact 0.5
  title 'Ensure journald is configured to write log files to persistent disk'
  tag domain: 'Logging (journald)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.2.1.1.5'
  tag level_cis: '1'
  tag ssg: 'journald_storage'
  describe command('grep -rqiE \'^[[:space:]]*Storage[[:space:]]*=[[:space:]]*persistent\b\' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
