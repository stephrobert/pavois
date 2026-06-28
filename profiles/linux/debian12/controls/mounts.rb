# Rendered from pavois reference (pavois-content/debian12.yml). Do not edit by hand.

control 'mount-boot-noexec' do
  impact 0.5
  title 'Add noexec Option to /boot'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag level_bp28: 'intermediary'
  tag ssg: 'mount_option_boot_noexec'
  describe mount('/boot') do
    its('options') { should include 'noexec' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /boot 2>/dev/null; grep -hsE '[[:space:]]/boot[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /boot 2>/dev/null) 2>/dev/null; } | grep -ow 'noexec'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-boot-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /boot'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_bp28: 'intermediary'
  tag ssg: 'mount_option_boot_nosuid'
  describe mount('/boot') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /boot 2>/dev/null; grep -hsE '[[:space:]]/boot[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /boot 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-dev-shm-nodev' do
  impact 0.5
  title 'Add nodev Option to /dev/shm'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.2.2'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_dev_shm_nodev'
  describe mount('/dev/shm') do
    its('options') { should include 'nodev' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /dev/shm 2>/dev/null; grep -hsE '[[:space:]]/dev/shm[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /dev/shm 2>/dev/null) 2>/dev/null; } | grep -ow 'nodev'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-dev-shm-noexec' do
  impact 0.5
  title 'Add noexec Option to /dev/shm'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.2.4'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_dev_shm_noexec'
  describe mount('/dev/shm') do
    its('options') { should include 'noexec' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /dev/shm 2>/dev/null; grep -hsE '[[:space:]]/dev/shm[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /dev/shm 2>/dev/null) 2>/dev/null; } | grep -ow 'noexec'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-dev-shm-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /dev/shm'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.2.3'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_dev_shm_nosuid'
  describe mount('/dev/shm') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /dev/shm 2>/dev/null; grep -hsE '[[:space:]]/dev/shm[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /dev/shm 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-home-nodev' do
  impact 0.5
  title 'Add nodev Option to /home'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.3.2'
  tag level_cis: '1'
  tag ssg: 'mount_option_home_nodev'
  describe mount('/home') do
    its('options') { should include 'nodev' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /home 2>/dev/null; grep -hsE '[[:space:]]/home[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /home 2>/dev/null) 2>/dev/null; } | grep -ow 'nodev'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-home-noexec' do
  impact 0.5
  title 'Add noexec Option to /home'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag nist: 'CM-6(b)'
  tag level_bp28: 'intermediary'
  tag ssg: 'mount_option_home_noexec'
  describe mount('/home') do
    its('options') { should include 'noexec' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /home 2>/dev/null; grep -hsE '[[:space:]]/home[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /home 2>/dev/null) 2>/dev/null; } | grep -ow 'noexec'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-home-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /home'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag cis: '1.1.2.3.3'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'mount_option_home_nosuid'
  describe mount('/home') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /home 2>/dev/null; grep -hsE '[[:space:]]/home[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /home 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-opt-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /opt'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag level_bp28: 'intermediary'
  tag ssg: 'mount_option_opt_nosuid'
  describe mount('/opt') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /opt 2>/dev/null; grep -hsE '[[:space:]]/opt[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /opt 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-srv-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /srv'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag level_bp28: 'intermediary'
  tag ssg: 'mount_option_srv_nosuid'
  describe mount('/srv') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /srv 2>/dev/null; grep -hsE '[[:space:]]/srv[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /srv 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-tmp-nodev' do
  impact 0.5
  title 'Add nodev Option to /tmp'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.1.2'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_tmp_nodev'
  describe mount('/tmp') do
    its('options') { should include 'nodev' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /tmp 2>/dev/null; grep -hsE '[[:space:]]/tmp[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /tmp 2>/dev/null) 2>/dev/null; } | grep -ow 'nodev'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-tmp-noexec' do
  impact 0.5
  title 'Add noexec Option to /tmp'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag cis: '1.1.2.1.4'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'mount_option_tmp_noexec'
  describe mount('/tmp') do
    its('options') { should include 'noexec' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /tmp 2>/dev/null; grep -hsE '[[:space:]]/tmp[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /tmp 2>/dev/null) 2>/dev/null; } | grep -ow 'noexec'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-tmp-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /tmp'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag cis: '1.1.2.1.3'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'mount_option_tmp_nosuid'
  describe mount('/tmp') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /tmp 2>/dev/null; grep -hsE '[[:space:]]/tmp[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /tmp 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-log-audit-nodev' do
  impact 0.5
  title 'Add nodev Option to /var/log/audit'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.7.2'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_var_log_audit_nodev'
  describe mount('/var/log/audit') do
    its('options') { should include 'nodev' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/log/audit 2>/dev/null; grep -hsE '[[:space:]]/var/log/audit[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/log/audit 2>/dev/null) 2>/dev/null; } | grep -ow 'nodev'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-log-audit-noexec' do
  impact 0.5
  title 'Add noexec Option to /var/log/audit'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.7.4'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_var_log_audit_noexec'
  describe mount('/var/log/audit') do
    its('options') { should include 'noexec' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/log/audit 2>/dev/null; grep -hsE '[[:space:]]/var/log/audit[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/log/audit 2>/dev/null) 2>/dev/null; } | grep -ow 'noexec'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-log-audit-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /var/log/audit'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.7.3'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_var_log_audit_nosuid'
  describe mount('/var/log/audit') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/log/audit 2>/dev/null; grep -hsE '[[:space:]]/var/log/audit[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/log/audit 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-log-nodev' do
  impact 0.5
  title 'Add nodev Option to /var/log'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.6.2'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_var_log_nodev'
  describe mount('/var/log') do
    its('options') { should include 'nodev' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/log 2>/dev/null; grep -hsE '[[:space:]]/var/log[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/log 2>/dev/null) 2>/dev/null; } | grep -ow 'nodev'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-log-noexec' do
  impact 0.5
  title 'Add noexec Option to /var/log'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag cis: '1.1.2.6.4'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'mount_option_var_log_noexec'
  describe mount('/var/log') do
    its('options') { should include 'noexec' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/log 2>/dev/null; grep -hsE '[[:space:]]/var/log[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/log 2>/dev/null) 2>/dev/null; } | grep -ow 'noexec'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-log-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /var/log'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag cis: '1.1.2.6.3'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'mount_option_var_log_nosuid'
  describe mount('/var/log') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/log 2>/dev/null; grep -hsE '[[:space:]]/var/log[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/log 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-nodev' do
  impact 0.5
  title 'Add nodev Option to /var'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.4.2'
  tag nist: ['AC-6', 'AC-6(1)', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'MP-7']
  tag level_cis: '1'
  tag ssg: 'mount_option_var_nodev'
  describe mount('/var') do
    its('options') { should include 'nodev' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var 2>/dev/null; grep -hsE '[[:space:]]/var[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var 2>/dev/null) 2>/dev/null; } | grep -ow 'nodev'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-noexec' do
  impact 0.5
  title 'Add noexec Option to /var'
  desc 'pavois does not auto-apply noexec to /var on Debian: dpkg executes maintainer scripts from /var/lib/dpkg/info, so noexec on /var breaks apt/dpkg (postinst Permission denied). CIS deliberately omits /var noexec for this reason (only nodev,nosuid); ANSSI R28 lists it but it is incompatible with Debian package management. Apply manually only if you accept this.'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag level_bp28: 'intermediary'
  tag ssg: 'mount_option_var_noexec'
  describe mount('/var') do
    its('options') { should include 'noexec' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var 2>/dev/null; grep -hsE '[[:space:]]/var[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var 2>/dev/null) 2>/dev/null; } | grep -ow 'noexec'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /var'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag cis: '1.1.2.4.3'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'mount_option_var_nosuid'
  describe mount('/var') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var 2>/dev/null; grep -hsE '[[:space:]]/var[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-tmp-nodev' do
  impact 0.5
  title 'Add nodev Option to /var/tmp'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '1.1.2.5.2'
  tag level_cis: '1'
  tag ssg: 'mount_option_var_tmp_nodev'
  describe mount('/var/tmp') do
    its('options') { should include 'nodev' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/tmp 2>/dev/null; grep -hsE '[[:space:]]/var/tmp[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/tmp 2>/dev/null) 2>/dev/null; } | grep -ow 'nodev'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-tmp-noexec' do
  impact 0.5
  title 'Add noexec Option to /var/tmp'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag cis: '1.1.2.5.4'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'mount_option_var_tmp_noexec'
  describe mount('/var/tmp') do
    its('options') { should include 'noexec' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/tmp 2>/dev/null; grep -hsE '[[:space:]]/var/tmp[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/tmp 2>/dev/null) 2>/dev/null; } | grep -ow 'noexec'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'mount-var-tmp-nosuid' do
  impact 0.5
  title 'Add nosuid Option to /var/tmp'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R28'
  tag cis: '1.1.2.5.3'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'mount_option_var_tmp_nosuid'
  describe mount('/var/tmp') do
    its('options') { should include 'nosuid' }
  end
  describe command("{ findmnt --fstab -no OPTIONS /var/tmp 2>/dev/null; grep -hsE '[[:space:]]/var/tmp[[:space:]]' /etc/fstab 2>/dev/null; systemctl show -p Options -- $(systemd-escape -p --suffix=mount /var/tmp 2>/dev/null) 2>/dev/null; } | grep -ow 'nosuid'") do
    its('stdout') { should match(/\S/) }
  end
end

control 'partition-boot' do
  impact 0.5
  title 'Ensure /boot Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R28'
  tag level_bp28: 'intermediary'
  tag ssg: 'partition_for_boot'
  describe mount('/boot') do
    it { should be_mounted }
  end
end

control 'partition-dev-shm' do
  impact 0.3
  title 'Ensure /dev/shm is configured'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '1.1.2.2.1'
  tag level_cis: '1'
  tag ssg: 'partition_for_dev_shm'
  describe mount('/dev/shm') do
    it { should be_mounted }
  end
end

control 'partition-home' do
  impact 0.3
  title 'Ensure /home Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R28'
  tag cis: '1.1.2.3.1'
  tag nist: ['CM-6(a)', 'SC-5(2)']
  tag level_bp28: 'intermediary'
  tag level_cis: '2'
  tag ssg: 'partition_for_home'
  describe mount('/home') do
    it { should be_mounted }
  end
end

control 'partition-opt' do
  impact 0.5
  title 'Ensure /opt Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R28'
  tag level_bp28: 'intermediary'
  tag ssg: 'partition_for_opt'
  describe mount('/opt') do
    it { should be_mounted }
  end
end

control 'partition-srv' do
  impact 0.5
  title 'Ensure /srv Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R28'
  tag level_bp28: 'intermediary'
  tag ssg: 'partition_for_srv'
  describe mount('/srv') do
    it { should be_mounted }
  end
end

control 'partition-tmp' do
  impact 0.3
  title 'Ensure /tmp Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '1.1.2.1.1'
  tag nist: ['CM-6(a)', 'SC-5(2)']
  tag level_cis: '1'
  tag ssg: 'partition_for_tmp'
  describe mount('/tmp') do
    it { should be_mounted }
  end
end

control 'partition-usr' do
  impact 0.5
  title 'Ensure /usr Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R28'
  tag level_bp28: 'intermediary'
  tag ssg: 'partition_for_usr'
  describe mount('/usr') do
    it { should be_mounted }
  end
end

control 'partition-var' do
  impact 0.3
  title 'Ensure /var Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R28'
  tag cis: '1.1.2.4.1'
  tag nist: ['CM-6(a)', 'SC-5(2)']
  tag level_bp28: 'intermediary'
  tag level_cis: '2'
  tag ssg: 'partition_for_var'
  describe mount('/var') do
    it { should be_mounted }
  end
end

control 'partition-var-log' do
  impact 0.3
  title 'Ensure /var/log Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R28'
  tag cis: '1.1.2.6.1'
  tag nist: ['AU-4', 'CM-6(a)', 'SC-5(2)']
  tag level_bp28: 'intermediary'
  tag level_cis: '2'
  tag ssg: 'partition_for_var_log'
  describe mount('/var/log') do
    it { should be_mounted }
  end
end

control 'partition-var-log-audit' do
  impact 0.3
  title 'Ensure /var/log/audit Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R71'
  tag cis: '1.1.2.7.1'
  tag nist: ['AU-4', 'CM-6(a)', 'SC-5(2)']
  tag level_bp28: 'enhanced'
  tag level_cis: '2'
  tag ssg: 'partition_for_var_log_audit'
  describe mount('/var/log/audit') do
    it { should be_mounted }
  end
end

control 'partition-var-tmp' do
  impact 0.5
  title 'Ensure /var/tmp Located On Separate Partition'
  tag domain: 'Mounts'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R28'
  tag cis: '1.1.2.5.1'
  tag level_bp28: 'intermediary'
  tag level_cis: '2'
  tag ssg: 'partition_for_var_tmp'
  describe mount('/var/tmp') do
    it { should be_mounted }
  end
end
