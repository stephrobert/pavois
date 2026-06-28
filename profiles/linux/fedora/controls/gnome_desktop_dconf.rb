# Rendered from pavois reference (pavois-content/fedora.yml). Do not edit by hand.

control 'dconf-gnome-banner-enabled' do
  impact 0.5
  title 'Enable GNOME3 Login Warning Banner'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.8.1'
  tag nist: ['3.1.9', 'AC-8(a)', 'AC-8(b)', 'AC-8(c)']
  tag level_cis: '1'
  tag ssg: 'dconf_gnome_banner_enabled'
  describe command('{ s=$(grep -rhE \'^[[:space:]]*banner-message-enable[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null | tail -1 | sed -E \'s/^[^=]*=[[:space:]]*//\' | tr -d "\'\\""); [ "$s" = "true" ] && grep -rqxF \'/org/gnome/login-screen/banner-message-enable\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-disable-automount' do
  impact 0.5
  title 'Disable GNOME3 Automounting'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.8.4'
  tag('pci-dss' => '3.4.2')
  tag nist: ['3.1.7', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'dconf_gnome_disable_automount'
  describe command('{ s=$(grep -rhE \'^[[:space:]]*automount[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null | tail -1 | sed -E \'s/^[^=]*=[[:space:]]*//\' | tr -d "\'\\""); [ "$s" = "false" ] && grep -rqxF \'/org/gnome/desktop/media-handling/automount\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-disable-automount-open' do
  impact 0.5
  title 'Disable GNOME3 Automount Opening'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.8.4'
  tag('pci-dss' => '3.4.2')
  tag nist: ['3.1.7', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'dconf_gnome_disable_automount_open'
  describe command('{ s=$(grep -rhE \'^[[:space:]]*automount-open[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null | tail -1 | sed -E \'s/^[^=]*=[[:space:]]*//\' | tr -d "\'\\""); [ "$s" = "false" ] && grep -rqxF \'/org/gnome/desktop/media-handling/automount-open\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-disable-autorun' do
  impact 0.3
  title 'Disable GNOME3 Automount running'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.8.5'
  tag nist: ['3.1.7', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'dconf_gnome_disable_autorun'
  describe command('{ s=$(grep -rhE \'^[[:space:]]*autorun-never[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null | tail -1 | sed -E \'s/^[^=]*=[[:space:]]*//\' | tr -d "\'\\""); [ "$s" = "true" ] && grep -rqxF \'/org/gnome/desktop/media-handling/autorun-never\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-disable-user-list' do
  impact 0.5
  title 'Disable the GNOME3 Login User List'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.8.2'
  tag nist: ['AC-23', 'CM-6(a)']
  tag level_cis: '1'
  tag ssg: 'dconf_gnome_disable_user_list'
  describe command('{ s=$(grep -rhE \'^[[:space:]]*disable-user-list[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null | tail -1 | sed -E \'s/^[^=]*=[[:space:]]*//\' | tr -d "\'\\""); [ "$s" = "true" ] && grep -rqxF \'/org/gnome/login-screen/disable-user-list\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-login-banner-text' do
  impact 0.5
  title 'Set the GNOME3 Login Warning Banner Text'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.8.1'
  tag nist: ['3.1.9', 'AC-8(a)', 'AC-8(c)']
  tag level_cis: '1'
  tag ssg: 'dconf_gnome_login_banner_text'
  describe command('{ grep -rqE \'^[[:space:]]*banner-message-text[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null && grep -rqxF \'/org/gnome/login-screen/banner-message-text\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-login-retries' do
  impact 0.5
  title 'Set the GNOME3 Login Number of Failures'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag nist: '3.1.8'
  tag ssg: 'dconf_gnome_login_retries'
  describe command('{ grep -rqE \'^[[:space:]]*allowed-failures[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null && grep -rqxF \'/org/gnome/login-screen/allowed-failures\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-screensaver-idle-activation-enabled' do
  impact 0.5
  title 'Enable GNOME3 Screensaver Idle Activation'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag('pci-dss' => '8.2.8')
  tag nist: '3.1.10'
  tag ssg: 'dconf_gnome_screensaver_idle_activation_enabled'
  describe command('{ s=$(grep -rhE \'^[[:space:]]*idle-activation-enabled[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null | tail -1 | sed -E \'s/^[^=]*=[[:space:]]*//\' | tr -d "\'\\""); [ "$s" = "true" ] && grep -rqxF \'/org/gnome/desktop/screensaver/idle-activation-enabled\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-screensaver-lock-enabled' do
  impact 0.5
  title 'Enable GNOME3 Screensaver Lock After Idle Period'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag('pci-dss' => '8.2.8')
  tag nist: ['CM-6(a)', '3.1.10']
  tag ssg: 'dconf_gnome_screensaver_lock_enabled'
  describe command('{ s=$(grep -rhE \'^[[:space:]]*lock-enabled[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null | tail -1 | sed -E \'s/^[^=]*=[[:space:]]*//\' | tr -d "\'\\""); [ "$s" = "true" ] && grep -rqxF \'/org/gnome/desktop/screensaver/lock-enabled\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-screensaver-mode-blank' do
  impact 0.5
  title 'Implement Blank Screensaver'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag('pci-dss' => '8.2.8')
  tag nist: ['3.1.10', 'AC-11(1)', 'AC-11(1).1', 'CM-6(a)']
  tag ssg: 'dconf_gnome_screensaver_mode_blank'
  describe command('{ grep -rqE \'^[[:space:]]*picture-uri[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null && grep -rqxF \'/org/gnome/desktop/screensaver/picture-uri\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-screensaver-user-info' do
  impact 0.5
  title 'Disable Full User Name on Splash Shield'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag ssg: 'dconf_gnome_screensaver_user_info'
  describe command('{ s=$(grep -rhE \'^[[:space:]]*show-full-name-in-top-bar[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null | tail -1 | sed -E \'s/^[^=]*=[[:space:]]*//\' | tr -d "\'\\""); [ "$s" = "false" ] && grep -rqxF \'/org/gnome/desktop/screensaver/show-full-name-in-top-bar\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-screensaver-user-locks' do
  impact 0.5
  title 'Ensure Users Cannot Change GNOME3 Screensaver Settings'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.8.3'
  tag nist: '3.1.10'
  tag level_cis: '1'
  tag ssg: 'dconf_gnome_screensaver_user_locks'
  describe command('{ grep -rqE \'^[[:space:]]*lock-delay[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null && grep -rqxF \'/org/gnome/desktop/screensaver/lock-delay\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end

control 'dconf-gnome-session-idle-user-locks' do
  impact 0.5
  title 'Ensure Users Cannot Change GNOME3 Session Idle Settings'
  tag domain: 'GNOME desktop (dconf)'
  tag evidence: 'persistent-config'
  tag reboot: 'yes'
  tag cis: '1.8.3'
  tag('pci-dss' => '8.2.8')
  tag nist: '3.1.10'
  tag level_cis: '1'
  tag ssg: 'dconf_gnome_session_idle_user_locks'
  describe command('{ grep -rqE \'^[[:space:]]*idle-delay[[:space:]]*=\' /etc/dconf/db/*.d/* 2>/dev/null && grep -rqxF \'/org/gnome/desktop/session/idle-delay\' /etc/dconf/db/*/locks/* 2>/dev/null && echo ok; } || echo ko') do
    its('stdout.strip') { should eq 'ok' }
  end
end
