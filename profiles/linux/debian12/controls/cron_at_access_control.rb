# Rendered from pavois reference (pavois-content/debian12.yml). Do not edit by hand.

control 'file-at-allow-exists' do
  impact 0.5
  title 'Ensure that /etc/at.allow exists'
  tag domain: 'Cron/at access control'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.2.1'
  tag level_cis: '1'
  tag ssg: 'file_at_allow_exists'
  describe file('/etc/at.allow') do
    it { should exist }
  end
end

control 'file-at-deny-absent' do
  impact 0.5
  title 'Ensure that /etc/at.deny does not exist'
  tag domain: 'Cron/at access control'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.2.1'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'file_at_deny_not_exist'
  describe file('/etc/at.deny') do
    it { should_not exist }
  end
end

control 'file-cron-allow-exists' do
  impact 0.5
  title 'Ensure that /etc/cron.allow exists'
  tag domain: 'Cron/at access control'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.1.2'
  tag level_cis: '1'
  tag ssg: 'file_cron_allow_exists'
  describe file('/etc/cron.allow') do
    it { should exist }
  end
end

control 'file-cron-deny-absent' do
  impact 0.5
  title 'Ensure that /etc/cron.deny does not exist'
  tag domain: 'Cron/at access control'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: ['2.2.6', '2.4.1.8']
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'file_cron_deny_not_exist'
  describe file('/etc/cron.deny') do
    it { should_not exist }
  end
end
