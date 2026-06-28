# Rendered from pavois reference (pavois-content/ubuntu2404.yml). Do not edit by hand.

control 'logging-present' do
  impact 0.5
  title 'A system logging daemon is active'
  tag domain: 'Logging'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '6.1.3.2'
  tag stig: 'UBTU-24-100200'
  tag level_cis: '1'
  tag ssg: 'logging-present'
  describe command('for s in rsyslog syslog-ng; do systemctl is-active --quiet "$s" && { echo ok; exit 0; }; done; echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
