# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'filegroupowner-at-allow' do
  impact 0.5
  title 'Verify Group Who Owns /etc/at.allow file'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.2.1'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'file_groupowner_at_allow'
  only_if { file('/etc/at.allow').exist? }
  describe file('/etc/at.allow') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-backup-etc-group' do
  impact 0.5
  title 'Verify Group Who Owns Backup group File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.1.4'
  tag('pci-dss' => '2.2.6')
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_backup_etc_group'
  only_if { file('/etc/group-').exist? }
  describe file('/etc/group-') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-backup-etc-gshadow' do
  impact 0.5
  title 'Verify Group Who Owns Backup gshadow File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.1.8'
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_backup_etc_gshadow'
  only_if { file('/etc/gshadow-').exist? }
  describe file('/etc/gshadow-') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-backup-etc-passwd' do
  impact 0.5
  title 'Verify Group Who Owns Backup passwd File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.1.2'
  tag('pci-dss' => '2.2.6')
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_backup_etc_passwd'
  only_if { file('/etc/passwd-').exist? }
  describe file('/etc/passwd-') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-backup-etc-shadow' do
  impact 0.5
  title 'Verify User Who Owns Backup shadow File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.1.6'
  tag('pci-dss' => '2.2.6')
  tag level_cis: '1'
  tag ssg: 'file_groupowner_backup_etc_shadow'
  only_if { file('/etc/shadow-').exist? }
  describe file('/etc/shadow-') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-cron-allow' do
  impact 0.5
  title 'Verify Group Who Owns /etc/cron.allow file'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.8'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_groupowner_cron_allow'
  only_if { file('/etc/cron.allow').exist? }
  describe file('/etc/cron.allow') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-cron-d' do
  impact 0.5
  title 'Verify Group Who Owns cron.d'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.7'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_groupowner_cron_d'
  only_if { file('/etc/cron.d').exist? }
  describe file('/etc/cron.d') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-cron-daily' do
  impact 0.5
  title 'Verify Group Who Owns cron.daily'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.4'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_groupowner_cron_daily'
  only_if { file('/etc/cron.daily').exist? }
  describe file('/etc/cron.daily') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-cron-deny' do
  impact 0.5
  title 'Verify Group Who Owns cron.deny'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'file_groupowner_cron_deny'
  only_if { file('/etc/cron.deny').exist? }
  describe file('/etc/cron.deny') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-cron-hourly' do
  impact 0.5
  title 'Verify Group Who Owns cron.hourly'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.3'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_groupowner_cron_hourly'
  only_if { file('/etc/cron.hourly').exist? }
  describe file('/etc/cron.hourly') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-cron-monthly' do
  impact 0.5
  title 'Verify Group Who Owns cron.monthly'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.6'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_groupowner_cron_monthly'
  only_if { file('/etc/cron.monthly').exist? }
  describe file('/etc/cron.monthly') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-cron-weekly' do
  impact 0.5
  title 'Verify Group Who Owns cron.weekly'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.5'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_groupowner_cron_weekly'
  only_if { file('/etc/cron.weekly').exist? }
  describe file('/etc/cron.weekly') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-crontab' do
  impact 0.5
  title 'Verify Group Who Owns Crontab'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_groupowner_crontab'
  only_if { file('/etc/crontab').exist? }
  describe file('/etc/crontab') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-crypttab' do
  impact 0.5
  title 'Verify Group Who Owns /etc/crypttab File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_groupowner_etc_crypttab'
  only_if { file('/etc/crypttab').exist? }
  describe file('/etc/crypttab') do
    its('group') { should eq 'root' }
  end
end

control 'filegroupowner-etc-group' do
  impact 0.5
  title 'Verify Group Who Owns group File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.3'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_etc_group'
  only_if { file('/etc/group').exist? }
  describe file('/etc/group') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-gshadow' do
  impact 0.5
  title 'Verify Group Who Owns gshadow File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.7'
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_etc_gshadow'
  only_if { file('/etc/gshadow').exist? }
  describe file('/etc/gshadow') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-ipsec-conf' do
  impact 0.5
  title 'Verify Group Who Owns /etc/ipsec.conf File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_groupowner_etc_ipsec_conf'
  only_if { file('/etc/ipsec.conf').exist? }
  describe file('/etc/ipsec.conf') do
    its('group') { should eq 'root' }
  end
end

control 'filegroupowner-etc-ipsec-secrets' do
  impact 0.5
  title 'Verify Group Who Owns /etc/ipsec.secrets File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_groupowner_etc_ipsec_secrets'
  only_if { file('/etc/ipsec.secrets').exist? }
  describe file('/etc/ipsec.secrets') do
    its('group') { should eq 'root' }
  end
end

control 'filegroupowner-etc-issue' do
  impact 0.5
  title 'Verify Group Ownership of System Login Banner'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '1.7.5'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_etc_issue'
  only_if { file('/etc/issue').exist? }
  describe file('/etc/issue') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-issue-net' do
  impact 0.5
  title 'Verify Group Ownership of System Login Banner for Remote Connections'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '1.7.6'
  tag('pci-dss' => '1.2.8')
  tag level_cis: '1'
  tag ssg: 'file_groupowner_etc_issue_net'
  only_if { file('/etc/issue.net').exist? }
  describe file('/etc/issue.net') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-motd' do
  impact 0.5
  title 'Verify Group Ownership of Message of the Day Banner'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '1.7.4'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_etc_motd'
  only_if { file('/etc/motd').exist? }
  describe file('/etc/motd') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-passwd' do
  impact 0.5
  title 'Verify Group Who Owns passwd File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.1'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_etc_passwd'
  only_if { file('/etc/passwd').exist? }
  describe file('/etc/passwd') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-sestatus-conf' do
  impact 0.5
  title 'Verify Group Who Owns /etc/sestatus.conf File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_groupowner_etc_sestatus_conf'
  only_if { file('/etc/sestatus.conf').exist? }
  describe file('/etc/sestatus.conf') do
    its('group') { should eq 'root' }
  end
end

control 'filegroupowner-etc-shadow' do
  impact 0.5
  title 'Verify Group Who Owns shadow File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.5'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_etc_shadow'
  only_if { file('/etc/shadow').exist? }
  describe file('/etc/shadow') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-shells' do
  impact 0.5
  title 'Verify Group Who Owns /etc/shells File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.9'
  tag nist: ['AC-3', 'MP-2']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_etc_shells'
  only_if { file('/etc/shells').exist? }
  describe file('/etc/shells') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-etc-sudoers' do
  impact 0.5
  title 'Verify Group Who Owns /etc/sudoers File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_groupowner_etc_sudoers'
  only_if { file('/etc/sudoers').exist? }
  describe file('/etc/sudoers') do
    its('group') { should eq 'root' }
  end
end

control 'filegroupowner-grub2-cfg' do
  impact 0.5
  title 'Verify /boot/grub2/grub.cfg Group Ownership'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag cis: '1.4.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.4.5', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_grub2_cfg'
  only_if { file('/boot/grub2/grub.cfg').exist? }
  describe file('/boot/grub2/grub.cfg') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-sshd-config' do
  impact 0.5
  title 'Verify Group Who Owns SSH Server config file'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '5.1.1'
  tag nist: ['AC-17(a)', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_sshd_config'
  only_if { file('/etc/ssh/sshd_config').exist? }
  describe file('/etc/ssh/sshd_config') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-systemmap' do
  impact 0.3
  title 'Verify Group Who Owns System.map Files'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag level_bp28: 'enhanced'
  tag ssg: 'file_groupowner_systemmap'
  only_if { file('/boot').exist? }
  describe file('/boot') do
    its('group') { should eq 'root' }
  end
end

control 'filegroupowner-user-cfg' do
  impact 0.5
  title 'Verify /boot/grub2/user.cfg Group Ownership'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag cis: '1.4.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.4.5', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_groupowner_user_cfg'
  only_if { file('/boot/grub2/user.cfg').exist? }
  describe file('/boot/grub2/user.cfg') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-var-log' do
  impact 0.5
  title 'Verify Group Who Owns /var/log Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'file_groupowner_var_log'
  only_if { file('/var/log').exist? }
  describe file('/var/log') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupowner-var-log-messages' do
  impact 0.5
  title 'Verify Group Who Owns /var/log/messages File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'file_groupowner_var_log_messages'
  only_if { file('/var/log/messages').exist? }
  describe file('/var/log/messages') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupownership-audit-binaries' do
  impact 0.5
  title 'Verify that audit tools are owned by group root'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '6.3.4.10'
  tag level_cis: '2'
  tag ssg: 'file_groupownership_audit_binaries'
  only_if { file('/sbin/auditctl').exist? }
  describe file('/sbin/auditctl') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupownership-audit-configuration' do
  impact 0.5
  title 'Audit Configuration Files Must Be Owned By Group root'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '6.3.4.7'
  tag level_cis: '2'
  tag ssg: 'file_groupownership_audit_configuration'
  only_if { file('/etc/audit').exist? }
  describe file('/etc/audit') do
    its('gid') { should eq 0 }
  end
end

control 'filegroupownership-sshd-private-key' do
  impact 0.5
  title 'Verify Group Ownership on SSH Server Private *_key Key Files'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '5.1.2'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_groupownership_sshd_private_key'
  only_if { file('/etc/ssh').exist? }
  describe file('/etc/ssh') do
    its('group') { should eq 'ssh_keys' }
  end
end

control 'filegroupownership-sshd-pub-key' do
  impact 0.5
  title 'Verify Group Ownership on SSH Server Public *.pub Key Files'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '5.1.3'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_groupownership_sshd_pub_key'
  only_if { file('/etc/ssh').exist? }
  describe file('/etc/ssh') do
    its('gid') { should eq 0 }
  end
end

control 'fileowner-at-allow' do
  impact 0.5
  title 'Verify User Who Owns /etc/at.allow file'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.2.1'
  tag('pci-dss' => '2.2.6')
  tag ssg: 'file_owner_at_allow'
  only_if { file('/etc/at.allow').exist? }
  describe file('/etc/at.allow') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-backup-etc-group' do
  impact 0.5
  title 'Verify User Who Owns Backup group File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.1.4'
  tag('pci-dss' => '2.2.6')
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_owner_backup_etc_group'
  only_if { file('/etc/group-').exist? }
  describe file('/etc/group-') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-backup-etc-gshadow' do
  impact 0.5
  title 'Verify User Who Owns Backup gshadow File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.1.8'
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_owner_backup_etc_gshadow'
  only_if { file('/etc/gshadow-').exist? }
  describe file('/etc/gshadow-') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-backup-etc-passwd' do
  impact 0.5
  title 'Verify User Who Owns Backup passwd File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.1.2'
  tag('pci-dss' => '2.2.6')
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_owner_backup_etc_passwd'
  only_if { file('/etc/passwd-').exist? }
  describe file('/etc/passwd-') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-backup-etc-shadow' do
  impact 0.5
  title 'Verify Group Who Owns Backup shadow File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '7.1.6'
  tag('pci-dss' => '2.2.6')
  tag nist: 'AC-6 (1)'
  tag level_cis: '1'
  tag ssg: 'file_owner_backup_etc_shadow'
  only_if { file('/etc/shadow-').exist? }
  describe file('/etc/shadow-') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-cron-allow' do
  impact 0.5
  title 'Verify User Who Owns /etc/cron.allow file'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.8'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_owner_cron_allow'
  only_if { file('/etc/cron.allow').exist? }
  describe file('/etc/cron.allow') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-cron-d' do
  impact 0.5
  title 'Verify Owner on cron.d'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.7'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_owner_cron_d'
  only_if { file('/etc/cron.d').exist? }
  describe file('/etc/cron.d') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-cron-daily' do
  impact 0.5
  title 'Verify Owner on cron.daily'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.4'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_owner_cron_daily'
  only_if { file('/etc/cron.daily').exist? }
  describe file('/etc/cron.daily') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-cron-deny' do
  impact 0.5
  title 'Verify Owner on cron.deny'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'file_owner_cron_deny'
  only_if { file('/etc/cron.deny').exist? }
  describe file('/etc/cron.deny') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-cron-hourly' do
  impact 0.5
  title 'Verify Owner on cron.hourly'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.3'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_owner_cron_hourly'
  only_if { file('/etc/cron.hourly').exist? }
  describe file('/etc/cron.hourly') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-cron-monthly' do
  impact 0.5
  title 'Verify Owner on cron.monthly'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.6'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_owner_cron_monthly'
  only_if { file('/etc/cron.monthly').exist? }
  describe file('/etc/cron.monthly') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-cron-weekly' do
  impact 0.5
  title 'Verify Owner on cron.weekly'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.5'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_owner_cron_weekly'
  only_if { file('/etc/cron.weekly').exist? }
  describe file('/etc/cron.weekly') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-crontab' do
  impact 0.5
  title 'Verify Owner on crontab'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '2.4.1.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'file_owner_crontab'
  only_if { file('/etc/crontab').exist? }
  describe file('/etc/crontab') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-crypttab' do
  impact 0.5
  title 'Verify User Who Owns /etc/crypttab File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_owner_etc_crypttab'
  only_if { file('/etc/crypttab').exist? }
  describe file('/etc/crypttab') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-group' do
  impact 0.5
  title 'Verify User Who Owns group File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.3'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_owner_etc_group'
  only_if { file('/etc/group').exist? }
  describe file('/etc/group') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-gshadow' do
  impact 0.5
  title 'Verify User Who Owns gshadow File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.7'
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_owner_etc_gshadow'
  only_if { file('/etc/gshadow').exist? }
  describe file('/etc/gshadow') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-ipsec-conf' do
  impact 0.5
  title 'Verify User Who Owns /etc/ipsec.conf File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_owner_etc_ipsec_conf'
  only_if { file('/etc/ipsec.conf').exist? }
  describe file('/etc/ipsec.conf') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-ipsec-secrets' do
  impact 0.5
  title 'Verify User Who Owns /etc/ipsec.secrets File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_owner_etc_ipsec_secrets'
  only_if { file('/etc/ipsec.secrets').exist? }
  describe file('/etc/ipsec.secrets') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-issue' do
  impact 0.5
  title 'Verify ownership of System Login Banner'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '1.7.5'
  tag level_cis: '1'
  tag ssg: 'file_owner_etc_issue'
  only_if { file('/etc/issue').exist? }
  describe file('/etc/issue') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-issue-net' do
  impact 0.5
  title 'Verify ownership of System Login Banner for Remote Connections'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '1.7.6'
  tag('pci-dss' => '1.2.8')
  tag level_cis: '1'
  tag ssg: 'file_owner_etc_issue_net'
  only_if { file('/etc/issue.net').exist? }
  describe file('/etc/issue.net') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-motd' do
  impact 0.5
  title 'Verify ownership of Message of the Day Banner'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '1.7.4'
  tag level_cis: '1'
  tag ssg: 'file_owner_etc_motd'
  only_if { file('/etc/motd').exist? }
  describe file('/etc/motd') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-passwd' do
  impact 0.5
  title 'Verify User Who Owns passwd File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.1'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_owner_etc_passwd'
  only_if { file('/etc/passwd').exist? }
  describe file('/etc/passwd') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-sestatus-conf' do
  impact 0.5
  title 'Verify User Who Owns /etc/sestatus.conf File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_owner_etc_sestatus_conf'
  only_if { file('/etc/sestatus.conf').exist? }
  describe file('/etc/sestatus.conf') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-shadow' do
  impact 0.5
  title 'Verify User Who Owns shadow File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.5'
  tag('pci-dss' => '2.2.6')
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_owner_etc_shadow'
  only_if { file('/etc/shadow').exist? }
  describe file('/etc/shadow') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-shells' do
  impact 0.5
  title 'Verify Who Owns /etc/shells File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '7.1.9'
  tag nist: ['AC-3', 'MP-2']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_owner_etc_shells'
  only_if { file('/etc/shells').exist? }
  describe file('/etc/shells') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-etc-sudoers' do
  impact 0.5
  title 'Verify User Who Owns /etc/sudoers File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'file_owner_etc_sudoers'
  only_if { file('/etc/sudoers').exist? }
  describe file('/etc/sudoers') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-grub2-cfg' do
  impact 0.5
  title 'Verify /boot/grub2/grub.cfg User Ownership'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag cis: '1.4.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.4.5', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_owner_grub2_cfg'
  only_if { file('/boot/grub2/grub.cfg').exist? }
  describe file('/boot/grub2/grub.cfg') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-sshd-config' do
  impact 0.5
  title 'Verify Owner on SSH Server config file'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: '5.1.1'
  tag nist: ['AC-17(a)', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_owner_sshd_config'
  only_if { file('/etc/ssh/sshd_config').exist? }
  describe file('/etc/ssh/sshd_config') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-systemmap' do
  impact 0.3
  title 'Verify User Who Owns System.map Files'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag level_bp28: 'enhanced'
  tag ssg: 'file_owner_systemmap'
  only_if { file('/boot').exist? }
  describe file('/boot') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-user-cfg' do
  impact 0.5
  title 'Verify /boot/grub2/user.cfg User Ownership'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R29'
  tag cis: '1.4.2'
  tag('pci-dss' => '2.2.6')
  tag nist: ['3.4.5', 'AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'enhanced'
  tag level_cis: '1'
  tag ssg: 'file_owner_user_cfg'
  only_if { file('/boot/grub2/user.cfg').exist? }
  describe file('/boot/grub2/user.cfg') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-var-log' do
  impact 0.5
  title 'Verify User Who Owns /var/log Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'file_owner_var_log'
  only_if { file('/var/log').exist? }
  describe file('/var/log') do
    its('uid') { should eq 0 }
  end
end

control 'fileowner-var-log-messages' do
  impact 0.5
  title 'Verify User Who Owns /var/log/messages File'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'file_owner_var_log_messages'
  only_if { file('/var/log/messages').exist? }
  describe file('/var/log/messages') do
    its('uid') { should eq 0 }
  end
end

control 'fileownership-audit-binaries' do
  impact 0.5
  title 'Verify that audit tools are owned by root'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '6.3.4.9'
  tag level_cis: '2'
  tag ssg: 'file_ownership_audit_binaries'
  only_if { file('/sbin/auditctl').exist? }
  describe file('/sbin/auditctl') do
    its('uid') { should eq 0 }
  end
end

control 'fileownership-audit-configuration' do
  impact 0.5
  title 'Audit Configuration Files Must Be Owned By Root'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag cis: '6.3.4.6'
  tag level_cis: '2'
  tag ssg: 'file_ownership_audit_configuration'
  only_if { file('/etc/audit').exist? }
  describe file('/etc/audit') do
    its('uid') { should eq 0 }
  end
end

control 'fileownership-sshd-pub-key' do
  impact 0.5
  title 'Verify Ownership on SSH Server Public *.pub Key Files'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag cis: ['5.1.2', '5.1.3']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'file_ownership_sshd_pub_key'
  only_if { file('/etc/ssh').exist? }
  describe file('/etc/ssh') do
    its('uid') { should eq 0 }
  end
end

control 'ownership-library-dirs' do
  impact 0.5
  title 'Verify that Shared Library Files Have Root Ownership'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'file_ownership_library_dirs'
  only_if { command('test -d /lib').exit_status.zero? }
  describe command('timeout 60 find -P /lib -type f ! -user 0 2>/dev/null | head -1') do
    its('stdout.strip') { should eq '' }
  end
end

control 'repgroupowner-etc-ipsecd' do
  impact 0.5
  title 'Verify Group Who Owns /etc/ipsec.d Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_groupowner_etc_ipsecd'
  only_if { file('/etc/ipsec.d').exist? }
  describe file('/etc/ipsec.d') do
    its('group') { should eq 'root' }
  end
end

control 'repgroupowner-etc-selinux' do
  impact 0.5
  title 'Verify Group Who Owns /etc/selinux Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_groupowner_etc_selinux'
  only_if { file('/etc/selinux').exist? }
  describe file('/etc/selinux') do
    its('group') { should eq 'root' }
  end
end

control 'repgroupowner-etc-sudoersd' do
  impact 0.5
  title 'Verify Group Who Owns /etc/sudoers.d Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_groupowner_etc_sudoersd'
  only_if { file('/etc/sudoers.d').exist? }
  describe file('/etc/sudoers.d') do
    its('group') { should eq 'root' }
  end
end

control 'repgroupowner-etc-sysctld' do
  impact 0.5
  title 'Verify Group Who Owns /etc/sysctl.d Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_groupowner_etc_sysctld'
  only_if { file('/etc/sysctl.d').exist? }
  describe file('/etc/sysctl.d') do
    its('group') { should eq 'root' }
  end
end

control 'repgroupowner-sshd-config-d' do
  impact 0.5
  title 'Verify Group Who Owns SSH Server Configuration Files'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'directory_groupowner_sshd_config_d'
  only_if { file('/etc/ssh/sshd_config.d').exist? }
  describe file('/etc/ssh/sshd_config.d') do
    its('gid') { should eq 0 }
  end
end

control 'repowner-etc-ipsecd' do
  impact 0.5
  title 'Verify User Who Owns /etc/ipsec.d Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_owner_etc_ipsecd'
  only_if { file('/etc/ipsec.d').exist? }
  describe file('/etc/ipsec.d') do
    its('uid') { should eq 0 }
  end
end

control 'repowner-etc-selinux' do
  impact 0.5
  title 'Verify User Who Owns /etc/selinux Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_owner_etc_selinux'
  only_if { file('/etc/selinux').exist? }
  describe file('/etc/selinux') do
    its('uid') { should eq 0 }
  end
end

control 'repowner-etc-sudoersd' do
  impact 0.5
  title 'Verify User Who Owns /etc/sudoers.d Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_owner_etc_sudoersd'
  only_if { file('/etc/sudoers.d').exist? }
  describe file('/etc/sudoers.d') do
    its('uid') { should eq 0 }
  end
end

control 'repowner-etc-sysctld' do
  impact 0.5
  title 'Verify User Who Owns /etc/sysctl.d Directory'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag bp28: 'R50'
  tag level_bp28: 'intermediary'
  tag ssg: 'directory_owner_etc_sysctld'
  only_if { file('/etc/sysctl.d').exist? }
  describe file('/etc/sysctl.d') do
    its('uid') { should eq 0 }
  end
end

control 'repowner-sshd-config-d' do
  impact 0.5
  title 'Verify Owner on SSH Server Configuration Files'
  tag domain: 'File ownership'
  tag evidence: 'filesystem-state'
  tag reboot: 'yes'
  tag ssg: 'directory_owner_sshd_config_d'
  only_if { file('/etc/ssh/sshd_config.d').exist? }
  describe file('/etc/ssh/sshd_config.d') do
    its('uid') { should eq 0 }
  end
end
