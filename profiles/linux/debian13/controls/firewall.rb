# Rendered from pavois reference (pavois-content/debian13.yml). Do not edit by hand.

control 'firewall-present' do
  impact 0.7
  title 'A host firewall is installed and active'
  tag domain: 'Firewall'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R50'
  tag nist: '3.1.3'
  tag level_bp28: 'intermediary'
  tag ssg: 'firewall-present'
  describe command('for s in ufw nftables firewalld; do systemctl is-active --quiet "$s" && { echo ok; exit 0; }; done; echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
