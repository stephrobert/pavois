# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'root-path' do
  impact 0.5
  title 'Ensure that All Entries in The Path of Root Are Directories'
  tag domain: 'Accounts (root PATH)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '5.4.2.5'
  tag level_cis: '1'
  tag ssg: 'root_path_all_dirs'
  rp = os_env('PATH').content.to_s.split(':')
  describe rp do
    it { should_not be_empty }
    it { should_not include '' }
    it { should_not include '.' }
  end
  rp.reject { |d| d.empty? || d == '.' }.each do |d|
    describe file(d) do
      it { should_not be_writable.by 'group' }
      it { should_not be_writable.by 'other' }
    end
  end
end
