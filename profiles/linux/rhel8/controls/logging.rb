# Rendered from pavois reference (pavois-content/rhel8.yml). Do not edit by hand.

control 'logging-present' do
  impact 0.5
  title 'A system logging daemon is active'
  tag domain: 'Logging'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R71'
  tag cis: '6.2.2.2'
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'logging-present'
  describe command('for s in rsyslog syslog-ng; do systemctl is-active --quiet "$s" && { echo ok; exit 0; }; done; echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
