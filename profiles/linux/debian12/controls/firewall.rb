# Rendered from pavois reference (pavois-content/debian12.yml). Do not edit by hand.

control 'firewall-default-deny' do
  impact 0.7
  title 'Ensure the Host Firewall Defaults to Deny (any backend)'
  tag domain: 'Firewall'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: ['4.2.7', '4.3.8', '4.4.2.1']
  tag('pci-dss' => '1.3.1')
  tag nist: ['CA-3(5)', 'CM-7(b)', 'SC-7(23)', 'CM-6(a)']
  tag level_cis: ['1', '2']
  tag ssg: 'firewall_default_deny_aggregated'
  describe command('if nft list ruleset 2>/dev/null | grep -qE \'hook input.*policy drop\' || iptables -S INPUT 2>/dev/null | grep -qE \'^-P INPUT (DROP|REJECT)\'; then echo ok; else echo ko; fi') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'firewall-present' do
  impact 0.7
  title 'A host firewall is installed and active'
  tag domain: 'Firewall'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R50'
  tag cis: ['4.1.1', '4.2.3']
  tag('pci-dss' => '1.2.1')
  tag nist: '3.1.3'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'firewall-present'
  describe command('for s in ufw nftables firewalld; do systemctl is-active --quiet "$s" && { echo ok; exit 0; }; done; echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
