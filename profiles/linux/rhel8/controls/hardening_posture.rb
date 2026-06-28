# Rendered from pavois reference (pavois-content/rhel8.yml). Do not edit by hand.

control 'posture-aslr' do
  impact 0.7
  title 'Address space layout randomization (ASLR) maximized'
  tag domain: 'Hardening (posture)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag posture: 'durcissement'
  tag ssg: 'posture-aslr'
  describe command('[ "$(sysctl -n kernel.randomize_va_space 2>/dev/null)" = "2" ] && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'posture-core-dumps-limits' do
  impact 0.5
  title 'Core dumps disabled (limits hard core 0)'
  tag domain: 'Hardening (posture)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag posture: 'durcissement'
  tag ssg: 'posture-core-dumps-limits'
  describe command('grep -rqE \'^\\*[[:space:]]+hard[[:space:]]+core[[:space:]]+0\' /etc/security/limits.conf /etc/security/limits.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'posture-file-integrity' do
  impact 0.5
  title 'A file integrity tool is installed'
  tag domain: 'Hardening (posture)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag posture: 'durcissement'
  tag ssg: 'posture-file-integrity'
  describe command('for c in aide tripwire aa-status; do command -v $c >/dev/null 2>&1 && { echo ok; exit; }; done; echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'posture-malware-scanner' do
  impact 0.5
  title 'An anti-malware tool is installed'
  tag domain: 'Hardening (posture)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag posture: 'durcissement'
  tag ssg: 'posture-malware-scanner'
  describe command('for c in rkhunter chkrootkit clamscan; do command -v $c >/dev/null 2>&1 && { echo ok; exit; }; done; echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'posture-no-autologin' do
  impact 0.7
  title 'No automatic login configured'
  tag domain: 'Hardening (posture)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag posture: 'durcissement'
  tag ssg: 'posture-no-autologin'
  describe command('grep -rqiE \'^[^#]*autologin\' /etc/gdm3 /etc/gdm /etc/lightdm 2>/dev/null && echo ko || echo ok') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'posture-no-compilers' do
  impact 0.5
  title 'No compiler available (attack surface)'
  tag domain: 'Hardening (posture)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag posture: 'durcissement'
  tag ssg: 'posture-no-compilers'
  describe command('for c in gcc cc clang g++ tcc; do command -v $c >/dev/null 2>&1 && echo $c; done') do
    its('stdout.strip') { should eq '' }
  end
end

control 'posture-process-accounting' do
  impact 0.3
  title 'Process accounting enabled'
  tag domain: 'Hardening (posture)'
  tag evidence: 'effective-runtime'
  tag reboot: 'no'
  tag posture: 'durcissement'
  tag ssg: 'posture-process-accounting'
  describe command('systemctl is-active auditd acct psacct 2>/dev/null | grep -q \'^active\' && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'posture-sysstat' do
  impact 0.3
  title 'System statistics collection (sysstat)'
  tag domain: 'Hardening (posture)'
  tag evidence: 'inventory-state'
  tag reboot: 'yes'
  tag posture: 'durcissement'
  tag ssg: 'posture-sysstat'
  describe command('command -v sar >/dev/null 2>&1 && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
