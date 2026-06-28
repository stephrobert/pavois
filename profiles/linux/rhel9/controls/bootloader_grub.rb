# Rendered from pavois reference (pavois-content/rhel9.yml). Do not edit by hand.

control 'grub-password' do
  impact 0.7
  title 'Set Boot Loader Password in grub2'
  tag domain: 'Bootloader (grub)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag bp28: 'R5'
  tag cis: '1.4.1'
  tag nist: ['3.4.5', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'grub2_password'
  describe command('grep -rqsE \'^[[:space:]]*(set[[:space:]]+superusers|password_pbkdf2|password)\' /boot/grub/grub.cfg /boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg /etc/grub.d/ 2>/dev/null && echo ok || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
