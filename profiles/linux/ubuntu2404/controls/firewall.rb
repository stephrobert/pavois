# Rendered from pavois reference (pavois-content/ubuntu2404.yml). Do not edit by hand.

control 'firewall-present' do
  impact 0.7
  title 'A host firewall is installed and active'
  tag domain: 'Firewall'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '4.2.3'
  tag('pci-dss' => '1.2.1')
  tag nist: '3.1.3'
  tag stig: 'UBTU-24-100300'
  tag level_cis: '1'
  tag ssg: 'firewall-present'
  describe command('for s in ufw nftables firewalld; do systemctl is-active --quiet "$s" && { echo ok; exit 0; }; done; echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
