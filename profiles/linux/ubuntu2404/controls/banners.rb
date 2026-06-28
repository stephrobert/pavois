# Rendered from pavois reference (pavois-content/ubuntu2404.yml). Do not edit by hand.

control 'banner-issue' do
  impact 0.5
  title 'Ensure Local Login Warning Banner Is Configured Properly'
  tag domain: 'Banners'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.6.2'
  tag level_cis: '1'
  tag ssg: 'banner_etc_issue_cis'
  describe file('/etc/issue') do
    its('content') { should match(/\S/) }
    its('content') { should_not match(/\\[smrvlSMRVL]/) }
  end
end

control 'banner-issue-net' do
  impact 0.5
  title 'Ensure Remote Login Warning Banner Is Configured Properly'
  tag domain: 'Banners'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.6.3'
  tag level_cis: '1'
  tag ssg: 'banner_etc_issue_net_cis'
  describe file('/etc/issue.net') do
    its('content') { should match(/\S/) }
    its('content') { should_not match(/\\[smrvlSMRVL]/) }
  end
end

control 'banner-motd' do
  impact 0.5
  title 'Ensure Message Of The Day Is Configured Properly'
  tag domain: 'Banners'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.6.1'
  tag level_cis: '1'
  tag ssg: 'banner_etc_motd_cis'
  describe file('/etc/motd') do
    its('content') { should match(/\S/) }
    its('content') { should_not match(/\\[smrvlSMRVL]/) }
  end
end
