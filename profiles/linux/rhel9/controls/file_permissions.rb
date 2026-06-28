# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'fileperm-at-allow' do
  impact 0.5
  title 'Verify Permissions on /etc/at.allow file'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.2.1'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'file_permissions_at_allow'
  only_if { file('/etc/at.allow').exist? }
  describe file('/etc/at.allow') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-audit-binaries' do
  impact 0.5
  title 'Verify that audit tools Have Mode 0755 or less'
  tag domain: 'File permissions'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag cis: '6.3.4.8'
  tag level_cis: '2'
  tag ssg: 'file_permissions_audit_binaries'
  only_if { file('/sbin/auditctl').exist? }
  describe file('/sbin/auditctl') do
    it { should_not be_setuid }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-audit-configuration' do
  impact 0.5
  title 'Audit Configuration Files Permissions are 640 or More Restrictive'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.4.5'
  tag nist: 'AU-12 b'
  tag level_cis: '2'
  tag ssg: 'file_permissions_audit_configuration'
  only_if { file('/etc/audit').exist? }
  describe file('/etc/audit') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-backup-etc-group' do
  impact 0.5
  title 'Verify Permissions on Backup group File'
  tag domain: 'File permissions'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.1.4'
  tag('pci-dss' => '2.2.6')
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_permissions_backup_etc_group'
  only_if { file('/etc/group-').exist? }
  describe file('/etc/group-') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-backup-etc-gshadow' do
  impact 0.5
  title 'Verify Permissions on Backup gshadow File'
  tag domain: 'File permissions'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.1.8'
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_permissions_backup_etc_gshadow'
  only_if { file('/etc/gshadow-').exist? }
  describe file('/etc/gshadow-') do
    it { should_not be_executable.by('owner') }
    it { should_not be_writable.by('owner') }
    it { should_not be_readable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-backup-etc-passwd' do
  impact 0.5
  title 'Verify Permissions on Backup passwd File'
  tag domain: 'File permissions'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.1.2'
  tag('pci-dss' => '2.2.6')
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_permissions_backup_etc_passwd'
  only_if { file('/etc/passwd-').exist? }
  describe file('/etc/passwd-') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-backup-etc-shadow' do
  impact 0.5
  title 'Verify Permissions on Backup shadow File'
  tag domain: 'File permissions'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag cis: '7.1.6'
  tag('pci-dss' => '2.2.6')
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_permissions_backup_etc_shadow'
  only_if { file('/etc/shadow-').exist? }
  describe file('/etc/shadow-') do
    it { should_not be_executable.by('owner') }
    it { should_not be_writable.by('owner') }
    it { should_not be_readable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-cron-allow' do
  impact 0.5
  title 'Verify Permissions on /etc/cron.allow file'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.1.8'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'file_permissions_cron_allow'
  only_if { file('/etc/cron.allow').exist? }
  describe file('/etc/cron.allow') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-cron-d' do
  impact 0.5
  title 'Verify Permissions on cron.d'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.1.7'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_permissions_cron_d'
  only_if { file('/etc/cron.d').exist? }
  describe file('/etc/cron.d') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-cron-daily' do
  impact 0.5
  title 'Verify Permissions on cron.daily'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.1.4'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_permissions_cron_daily'
  only_if { file('/etc/cron.daily').exist? }
  describe file('/etc/cron.daily') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-cron-hourly' do
  impact 0.5
  title 'Verify Permissions on cron.hourly'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.1.3'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_permissions_cron_hourly'
  only_if { file('/etc/cron.hourly').exist? }
  describe file('/etc/cron.hourly') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-cron-monthly' do
  impact 0.5
  title 'Verify Permissions on cron.monthly'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.1.6'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_permissions_cron_monthly'
  only_if { file('/etc/cron.monthly').exist? }
  describe file('/etc/cron.monthly') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-cron-weekly' do
  impact 0.5
  title 'Verify Permissions on cron.weekly'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.1.5'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_permissions_cron_weekly'
  only_if { file('/etc/cron.weekly').exist? }
  describe file('/etc/cron.weekly') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-crontab' do
  impact 0.5
  title 'Verify Permissions on crontab'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '2.4.1.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_permissions_crontab'
  only_if { file('/etc/crontab').exist? }
  describe file('/etc/crontab') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-efi-grub2-cfg' do
  impact 0.5
  title 'Verify the UEFI Boot Loader grub.cfg Permissions'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag nist: '3.4.5'
  tag level_bp28: 'enhanced'
  tag ssg: 'file_permissions_efi_grub2_cfg'
  only_if { file('/boot/grub2/grub.cfg').exist? }
  describe file('/boot/grub2/grub.cfg') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-efi-user-cfg' do
  impact 0.5
  title 'Verify /boot/grub2/user.cfg Permissions'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag nist: '3.4.5'
  tag level_bp28: 'enhanced'
  tag ssg: 'file_permissions_efi_user_cfg'
  only_if { file('/boot/grub2/user.cfg').exist? }
  describe file('/boot/grub2/user.cfg') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-audit-auditd' do
  impact 0.5
  title 'Verify Permissions on /etc/audit/auditd.conf'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'file_permissions_etc_audit_auditd'
  only_if { file('/etc/audit/auditd.conf').exist? }
  describe file('/etc/audit/auditd.conf') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-crypttab' do
  impact 0.5
  title 'Verify Permissions On /etc/crypttab File'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_permissions_etc_crypttab'
  only_if { file('/etc/crypttab').exist? }
  describe file('/etc/crypttab') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-group' do
  impact 0.5
  title 'Verify Permissions on group File'
  tag domain: 'File permissions'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.3'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_permissions_etc_group'
  only_if { file('/etc/group').exist? }
  describe file('/etc/group') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-gshadow' do
  impact 0.5
  title 'Verify Permissions on gshadow File'
  tag domain: 'File permissions'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.7'
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_permissions_etc_gshadow'
  only_if { file('/etc/gshadow').exist? }
  describe file('/etc/gshadow') do
    it { should_not be_executable.by('owner') }
    it { should_not be_writable.by('owner') }
    it { should_not be_readable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-ipsec-conf' do
  impact 0.5
  title 'Verify Permissions On /etc/ipsec.conf File'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_permissions_etc_ipsec_conf'
  only_if { file('/etc/ipsec.conf').exist? }
  describe file('/etc/ipsec.conf') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-ipsec-secrets' do
  impact 0.5
  title 'Verify Permissions On /etc/ipsec.secrets File'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_permissions_etc_ipsec_secrets'
  only_if { file('/etc/ipsec.secrets').exist? }
  describe file('/etc/ipsec.secrets') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-ipsecd' do
  impact 0.5
  title 'Verify Permissions On /etc/ipsec.d Directory'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_permissions_etc_ipsecd'
  only_if { file('/etc/ipsec.d').exist? }
  describe file('/etc/ipsec.d') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-issue' do
  impact 0.5
  title 'Verify permissions on System Login Banner'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.7.5'
  tag level_cis: '1'
  tag ssg: 'file_permissions_etc_issue'
  only_if { file('/etc/issue').exist? }
  describe file('/etc/issue') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-issue-net' do
  impact 0.5
  title 'Verify permissions on System Login Banner for Remote Connections'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.7.6'
  tag('pci-dss' => '1.2.8')
  tag level_cis: '1'
  tag ssg: 'file_permissions_etc_issue_net'
  only_if { file('/etc/issue.net').exist? }
  describe file('/etc/issue.net') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-motd' do
  impact 0.5
  title 'Verify permissions on Message of the Day Banner'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.7.4'
  tag level_cis: '1'
  tag ssg: 'file_permissions_etc_motd'
  only_if { file('/etc/motd').exist? }
  describe file('/etc/motd') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-passwd' do
  impact 0.5
  title 'Verify Permissions on passwd File'
  tag domain: 'File permissions'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.1'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_permissions_etc_passwd'
  only_if { file('/etc/passwd').exist? }
  describe file('/etc/passwd') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-selinux' do
  impact 0.5
  title 'Verify Permissions On /etc/selinux Directory'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_permissions_etc_selinux'
  only_if { file('/etc/selinux').exist? }
  describe file('/etc/selinux') do
    it { should_not be_setuid }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-sestatus-conf' do
  impact 0.5
  title 'Verify Permissions On /etc/sestatus.conf File'
  tag domain: 'File permissions'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_permissions_etc_sestatus_conf'
  only_if { file('/etc/sestatus.conf').exist? }
  describe file('/etc/sestatus.conf') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-shadow' do
  impact 0.5
  title 'Verify Permissions on shadow File'
  tag domain: 'File permissions'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.5'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_permissions_etc_shadow'
  only_if { file('/etc/shadow').exist? }
  describe file('/etc/shadow') do
    it { should_not be_executable.by('owner') }
    it { should_not be_writable.by('owner') }
    it { should_not be_readable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-shells' do
  impact 0.5
  title 'Verify Permissions on /etc/shells File'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.9'
  tag nist: ['AC-3', 'MP-2']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_permissions_etc_shells'
  only_if { file('/etc/shells').exist? }
  describe file('/etc/shells') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-sudoers' do
  impact 0.5
  title 'Verify Permissions On /etc/sudoers File'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_permissions_etc_sudoers'
  only_if { file('/etc/sudoers').exist? }
  describe file('/etc/sudoers') do
    it { should_not be_executable.by('owner') }
    it { should_not be_writable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-sudoersd' do
  impact 0.5
  title 'Verify Permissions On /etc/sudoers.d Directory'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_permissions_etc_sudoersd'
  only_if { file('/etc/sudoers.d').exist? }
  describe file('/etc/sudoers.d') do
    it { should_not be_setuid }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-etc-sysctld' do
  impact 0.5
  title 'Verify Permissions On /etc/sysctl.d Directory'
  tag domain: 'File permissions'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_permissions_etc_sysctld'
  only_if { file('/etc/sysctl.d').exist? }
  describe file('/etc/sysctl.d') do
    it { should_not be_setuid }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-grub2-cfg' do
  impact 0.5
  title 'Verify /boot/grub2/grub.cfg Permissions'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag cis: '1.4.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.4.5', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_permissions_grub2_cfg'
  only_if { file('/boot/grub2/grub.cfg').exist? }
  describe file('/boot/grub2/grub.cfg') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-library-dirs' do
  impact 0.5
  title 'Verify that Shared Library Files Have Restrictive Permissions'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'file_permissions_library_dirs'
  only_if { file('/lib').exist? }
  describe file('/lib') do
    it { should_not be_writable.by('group') }
    it { should_not be_writable.by('other') }
  end
end

control 'fileperm-sshd-config' do
  impact 0.5
  title 'Verify Permissions on SSH Server config file'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '5.1.1'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-17(a)', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_permissions_sshd_config'
  only_if { file('/etc/ssh/sshd_config').exist? }
  describe file('/etc/ssh/sshd_config') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-sshd-config-d' do
  impact 0.5
  title 'Verify Permissions on SSH Server Config File'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'directory_permissions_sshd_config_d'
  only_if { file('/etc/ssh/sshd_config.d').exist? }
  describe file('/etc/ssh/sshd_config.d') do
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-sshd-drop-in-config' do
  impact 0.5
  title 'Verify Permissions on SSH Server Config File'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'file_permissions_sshd_drop_in_config'
  only_if { file('/etc/ssh/sshd_config.d').exist? }
  describe file('/etc/ssh/sshd_config.d') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-sshd-pub-key' do
  impact 0.5
  title 'Verify Permissions on SSH Server Public *.pub Key Files'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '5.1.3'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.1.13', 'AC-17(a)', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_permissions_sshd_pub_key'
  only_if { file('/etc/ssh').exist? }
  describe file('/etc/ssh') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-sudo' do
  impact 0.5
  title 'Ensure That the sudo Binary Has the Correct Permissions'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R38'
  tag level_bp28: 'enhanced'
  tag ssg: 'file_permissions_sudo'
  only_if { file('/usr/bin/sudo').exist? }
  describe file('/usr/bin/sudo') do
    it { should_not be_readable.by('owner') }
    it { should_not be_writable.by('owner') }
    it { should_not be_readable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_executable.by('other') }
  end
end

control 'fileperm-systemmap' do
  impact 0.3
  title 'Verify Permissions on System.map Files'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag level_bp28: 'enhanced'
  tag ssg: 'file_permissions_systemmap'
  only_if { file('/boot').exist? }
  describe file('/boot') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-unauthorized-world-writable' do
  impact 0.5
  title 'Ensure No World-Writable Files Exist'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R54'
  tag cis: '7.1.11'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'minimal'
  tag level_cis: '1'
  tag ssg: 'file_permissions_unauthorized_world_writable'
  only_if { file('/tmp').exist? }
  describe file('/tmp') do
    it { should_not be_writable.by('other') }
  end
end

control 'fileperm-user-cfg' do
  impact 0.5
  title 'Verify /boot/grub2/user.cfg Permissions'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag cis: '1.4.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.4.5', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_permissions_user_cfg'
  only_if { file('/boot/grub2/user.cfg').exist? }
  describe file('/boot/grub2/user.cfg') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-var-log' do
  impact 0.5
  title 'Verify Permissions on /var/log Directory'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'file_permissions_var_log'
  only_if { file('/var/log').exist? }
  describe file('/var/log') do
    it { should_not be_setuid }
    it { should_not be_writable.by('group') }
    it { should_not be_setgid }
    it { should_not be_writable.by('other') }
    it { should_not be_sticky }
  end
end

control 'fileperm-var-log-audit' do
  impact 0.5
  title 'System Audit Logs Must Have Mode 0750 or Less Permissive'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '6.3.4.2'
  tag nist: ['3.3.1', 'AC-6(1)', 'AU-9(4)', 'CM-6(a)']
  tag level_cis: '2'
  tag ssg: 'file_permissions_var_log_audit'
  only_if { file('/var/log/audit').exist? }
  describe file('/var/log/audit') do
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_executable.by('other') }
  end
end

control 'fileperm-var-log-messages' do
  impact 0.5
  title 'Verify Permissions on /var/log/messages File'
  tag domain: 'File permissions'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'file_permissions_var_log_messages'
  only_if { file('/var/log/messages').exist? }
  describe file('/var/log/messages') do
    it { should_not be_executable.by('owner') }
    it { should_not be_setuid }
    it { should_not be_executable.by('group') }
    it { should_not be_writable.by('group') }
    it { should_not be_readable.by('group') }
    it { should_not be_setgid }
    it { should_not be_executable.by('other') }
    it { should_not be_writable.by('other') }
    it { should_not be_readable.by('other') }
    it { should_not be_sticky }
  end
end
