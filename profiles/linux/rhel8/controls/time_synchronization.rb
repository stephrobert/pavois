# Rendered from pavois reference (pavois-content/rhel8.yml). Do not edit by hand.

control 'time-sync-present' do
  impact 0.5
  title 'A time-synchronization service is active'
  tag domain: 'Time synchronization'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R71'
  tag cis: '2.3.1'
  tag('pci-dss' => '10.6.1')
  tag nist: ['3.3.7', 'SC-45']
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'time-sync-present'
  describe command('for s in chrony chronyd systemd-timesyncd ntp ntpsec; do systemctl is-active --quiet "$s" && { echo ok; exit 0; }; done; echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
