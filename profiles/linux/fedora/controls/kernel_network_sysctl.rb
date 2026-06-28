# Rendered from pavois reference (pavois-content/fedora.yml). Do not edit by hand.

control 'sysctl-fs-protected_hardlinks' do
  impact 0.5
  title 'Enable Kernel Parameter to Enforce DAC on Hardlinks'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R14'
  tag cis: '1.5.2'
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_fs_protected_hardlinks'
  describe kernel_parameter('fs.protected_hardlinks') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*fs.protected_hardlinks[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-fs-protected_symlinks' do
  impact 0.5
  title 'Enable Kernel Parameter to Enforce DAC on Symlinks'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R14'
  tag cis: '1.5.3'
  tag nist: ['AC-6(1)', 'CM-6(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_fs_protected_symlinks'
  describe kernel_parameter('fs.protected_symlinks') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*fs.protected_symlinks[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-fs-suid_dumpable' do
  impact 0.5
  title 'Disable Core Dumps for SUID programs'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R14'
  tag cis: '1.5.4'
  tag('pci-dss' => '3.3.1.1')
  tag nist: ['SI-11(a)', 'SI-11(b)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_fs_suid_dumpable'
  describe kernel_parameter('fs.suid_dumpable') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*fs.suid_dumpable[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-kernel-core_pattern' do
  impact 0.5
  title 'Disable storing core dumps'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag('pci-dss' => '3.3.1.1')
  tag ssg: 'sysctl_kernel_core_pattern'
  describe kernel_parameter('kernel.core_pattern') do
    its('value') { should cmp '|/bin/false' }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.core_pattern[[:space:]]*=[[:space:]]*|/bin/false([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-kernel-dmesg_restrict' do
  impact 0.3
  title 'Restrict Access to Kernel Message Buffer'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R9'
  tag cis: '1.5.5'
  tag nist: ['3.1.5', 'SI-11(a)', 'SI-11(b)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_kernel_dmesg_restrict'
  describe kernel_parameter('kernel.dmesg_restrict') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.dmesg_restrict[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-kernel-kexec_load_disabled' do
  impact 0.5
  title 'Disable Kernel Image Loading'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'sysctl_kernel_kexec_load_disabled'
  describe kernel_parameter('kernel.kexec_load_disabled') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.kexec_load_disabled[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-kernel-kptr_restrict' do
  impact 0.5
  title 'Restrict Exposed Kernel Pointer Addresses Access'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R9'
  tag cis: '1.5.6'
  tag nist: ['CM-6(a)', 'SC-30', 'SC-30(2)', 'SC-30(5)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_kernel_kptr_restrict'
  describe kernel_parameter('kernel.kptr_restrict') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.kptr_restrict[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-kernel-perf_event_paranoid' do
  impact 0.3
  title 'Disallow kernel profiling by unprivileged users'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R9'
  tag nist: 'AC-6'
  tag level_bp28: 'intermediary'
  tag ssg: 'sysctl_kernel_perf_event_paranoid'
  describe kernel_parameter('kernel.perf_event_paranoid') do
    its('value') { should cmp 2 }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.perf_event_paranoid[[:space:]]*=[[:space:]]*2([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-kernel-randomize_va_space' do
  impact 0.5
  title 'Enable Randomized Layout of Virtual Address Space'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R9'
  tag cis: '1.5.8'
  tag('pci-dss' => '3.3.1.1')
  tag nist: ['3.1.7', 'CM-6(a)', 'SC-30', 'SC-30(2)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_kernel_randomize_va_space'
  describe kernel_parameter('kernel.randomize_va_space') do
    its('value') { should cmp 2 }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.randomize_va_space[[:space:]]*=[[:space:]]*2([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-kernel-unprivileged_bpf_disabled' do
  impact 0.5
  title 'Disable Access to Network bpf() Syscall From Unprivileged Processes'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R9'
  tag nist: ['AC-6', 'SC-7(10)']
  tag level_bp28: 'intermediary'
  tag ssg: 'sysctl_kernel_unprivileged_bpf_disabled'
  describe kernel_parameter('kernel.unprivileged_bpf_disabled') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.unprivileged_bpf_disabled[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-kernel-yama-ptrace_scope' do
  impact 0.5
  title 'Restrict usage of ptrace to descendant processes'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R11'
  tag cis: '1.5.7'
  tag nist: 'SC-7(10)'
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_kernel_yama_ptrace_scope'
  describe kernel_parameter('kernel.yama.ptrace_scope') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*kernel.yama.ptrace_scope[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-core-bpf_jit_harden' do
  impact 0.5
  title 'Harden the operation of the BPF just-in-time compiler'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag nist: ['CM-6', 'SC-7(10)']
  tag level_bp28: 'intermediary'
  tag ssg: 'sysctl_net_core_bpf_jit_harden'
  describe kernel_parameter('net.core.bpf_jit_harden') do
    its('value') { should cmp 2 }
  end
  describe command("grep -hsE '^[[:space:]]*net.core.bpf_jit_harden[[:space:]]*=[[:space:]]*2([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-all-accept_redirects' do
  impact 0.5
  title 'Disable Accepting ICMP Redirects for All IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.8'
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_all_accept_redirects'
  describe kernel_parameter('net.ipv4.conf.all.accept_redirects') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.all.accept_redirects[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-all-accept_source_route' do
  impact 0.5
  title 'Disable Kernel Parameter for Accepting Source-Routed Packets on all IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.14'
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-5', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_all_accept_source_route'
  describe kernel_parameter('net.ipv4.conf.all.accept_source_route') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.all.accept_source_route[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-all-forwarding' do
  impact 0.5
  title 'Disable Kernel Parameter for IPv4 Forwarding on all IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.1.2'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_all_forwarding'
  describe kernel_parameter('net.ipv4.conf.all.forwarding') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.all.forwarding[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-all-log_martians' do
  impact 0.5
  title 'Enable Kernel Parameter to Log Martian Packets on all IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.1.16'
  tag nist: ['3.1.20', 'CM-7(a)', 'CM-7(b)', 'SC-5(3)(a)']
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_all_log_martians'
  describe kernel_parameter('net.ipv4.conf.all.log_martians') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.all.log_martians[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-all-rp_filter' do
  impact 0.5
  title 'Enable Kernel Parameter to Use Reverse Path Filtering on all IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.12'
  tag('pci-dss' => '1.4.3')
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_all_rp_filter'
  describe kernel_parameter('net.ipv4.conf.all.rp_filter') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.all.rp_filter[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-all-secure_redirects' do
  impact 0.5
  title 'Disable Kernel Parameter for Accepting Secure ICMP Redirects on all IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.10'
  tag('pci-dss' => '1.4.3')
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_all_secure_redirects'
  describe kernel_parameter('net.ipv4.conf.all.secure_redirects') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.all.secure_redirects[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-all-send_redirects' do
  impact 0.5
  title 'Disable Kernel Parameter for Sending ICMP Redirects on all IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.4'
  tag('pci-dss' => '1.4.5')
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-5', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_all_send_redirects'
  describe kernel_parameter('net.ipv4.conf.all.send_redirects') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.all.send_redirects[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-default-accept_redirects' do
  impact 0.5
  title 'Disable Kernel Parameter for Accepting ICMP Redirects by Default on IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.9'
  tag('pci-dss' => '1.4.3')
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_default_accept_redirects'
  describe kernel_parameter('net.ipv4.conf.default.accept_redirects') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.default.accept_redirects[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-default-accept_source_route' do
  impact 0.5
  title 'Disable Kernel Parameter for Accepting Source-Routed Packets on IPv4 Interfaces by Default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.15'
  tag nist: ['3.1.20', 'CM-7(a)', 'CM-7(b)', 'SC-5', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_default_accept_source_route'
  describe kernel_parameter('net.ipv4.conf.default.accept_source_route') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.default.accept_source_route[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-default-forwarding' do
  impact 0.5
  title 'Disable Kernel Parameter for IPv4 Forwarding By Default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.1.3'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_default_forwarding'
  describe kernel_parameter('net.ipv4.conf.default.forwarding') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.default.forwarding[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-default-log_martians' do
  impact 0.5
  title 'Enable Kernel Parameter to Log Martian Packets on all IPv4 Interfaces by Default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.1.17'
  tag nist: ['3.1.20', 'CM-7(a)', 'CM-7(b)', 'SC-5(3)(a)']
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_default_log_martians'
  describe kernel_parameter('net.ipv4.conf.default.log_martians') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.default.log_martians[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-default-rp_filter' do
  impact 0.5
  title 'Enable Kernel Parameter to Use Reverse Path Filtering on all IPv4 Interfaces by Default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.13'
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_default_rp_filter'
  describe kernel_parameter('net.ipv4.conf.default.rp_filter') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.default.rp_filter[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-default-secure_redirects' do
  impact 0.5
  title 'Configure Kernel Parameter for Accepting Secure Redirects By Default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.11'
  tag nist: ['3.1.20', 'CM-7(a)', 'CM-7(b)', 'SC-5', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_default_secure_redirects'
  describe kernel_parameter('net.ipv4.conf.default.secure_redirects') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.default.secure_redirects[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-conf-default-send_redirects' do
  impact 0.5
  title 'Disable Kernel Parameter for Sending ICMP Redirects on all IPv4 Interfaces by Default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.5'
  tag('pci-dss' => '1.4.5')
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-5', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_conf_default_send_redirects'
  describe kernel_parameter('net.ipv4.conf.default.send_redirects') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.conf.default.send_redirects[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-icmp_echo_ignore_broadcasts' do
  impact 0.5
  title 'Enable Kernel Parameter to Ignore ICMP Broadcast Echo Requests on IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.1.7'
  tag('pci-dss' => '1.4.2')
  tag nist: ['3.1.20', 'CM-7(a)', 'CM-7(b)', 'SC-5']
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_icmp_echo_ignore_broadcasts'
  describe kernel_parameter('net.ipv4.icmp_echo_ignore_broadcasts') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.icmp_echo_ignore_broadcasts[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-icmp_ignore_bogus_error_responses' do
  impact 0.5
  title 'Enable Kernel Parameter to Ignore Bogus ICMP Error Responses on IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.6'
  tag('pci-dss' => '1.4.2')
  tag nist: ['3.1.20', 'CM-7(a)', 'CM-7(b)', 'SC-5']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_icmp_ignore_bogus_error_responses'
  describe kernel_parameter('net.ipv4.icmp_ignore_bogus_error_responses') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.icmp_ignore_bogus_error_responses[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-ip_forward' do
  impact 0.5
  title 'Disable Kernel Parameter for IP Forwarding on IPv4 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.1'
  tag('pci-dss' => '1.4.3')
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-5', 'SC-7(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '2'
  tag ssg: 'sysctl_net_ipv4_ip_forward'
  describe kernel_parameter('net.ipv4.ip_forward') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.ip_forward[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv4-tcp_syncookies' do
  impact 0.5
  title 'Enable Kernel Parameter to Use TCP Syncookies on Network Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R12'
  tag cis: '3.3.1.18'
  tag('pci-dss' => '1.4.3')
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)', 'SC-5(1)', 'SC-5(2)', 'SC-5(3)(a)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv4_tcp_syncookies'
  describe kernel_parameter('net.ipv4.tcp_syncookies') do
    its('value') { should cmp 1 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv4.tcp_syncookies[[:space:]]*=[[:space:]]*1([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv6-conf-all-accept_ra' do
  impact 0.5
  title 'Configure Accepting Router Advertisements on All IPv6 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.2.7'
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv6_conf_all_accept_ra'
  describe kernel_parameter('net.ipv6.conf.all.accept_ra') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv6.conf.all.accept_ra[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv6-conf-all-accept_redirects' do
  impact 0.5
  title 'Disable Accepting ICMP Redirects for All IPv6 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R13'
  tag cis: '3.3.2.3'
  tag nist: ['3.1.20', 'CM-6', 'CM-6(a)', 'CM-6(b)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv6_conf_all_accept_redirects'
  describe kernel_parameter('net.ipv6.conf.all.accept_redirects') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv6.conf.all.accept_redirects[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv6-conf-all-accept_source_route' do
  impact 0.5
  title 'Disable Kernel Parameter for Accepting Source-Routed Packets on all IPv6 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R13'
  tag cis: '3.3.2.5'
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv6_conf_all_accept_source_route'
  describe kernel_parameter('net.ipv6.conf.all.accept_source_route') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv6.conf.all.accept_source_route[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv6-conf-all-forwarding' do
  impact 0.5
  title 'Disable Kernel Parameter for IPv6 Forwarding'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.2.1'
  tag nist: ['CM-6', 'CM-6(a)', 'CM-6(b)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv6_conf_all_forwarding'
  describe kernel_parameter('net.ipv6.conf.all.forwarding') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv6.conf.all.forwarding[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv6-conf-default-accept_ra' do
  impact 0.5
  title 'Disable Accepting Router Advertisements on all IPv6 Interfaces by Default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.2.8'
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv6_conf_default_accept_ra'
  describe kernel_parameter('net.ipv6.conf.default.accept_ra') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv6.conf.default.accept_ra[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv6-conf-default-accept_redirects' do
  impact 0.5
  title 'Disable Kernel Parameter for Accepting ICMP Redirects by Default on IPv6 Interfaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R13'
  tag cis: '3.3.2.4'
  tag nist: ['3.1.20', 'CM-6(a)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv6_conf_default_accept_redirects'
  describe kernel_parameter('net.ipv6.conf.default.accept_redirects') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv6.conf.default.accept_redirects[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv6-conf-default-accept_source_route' do
  impact 0.5
  title 'Disable Kernel Parameter for Accepting Source-Routed Packets on IPv6 Interfaces by Default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag bp28: 'R13'
  tag cis: '3.3.2.6'
  tag('pci-dss' => '1.4.2')
  tag nist: ['3.1.20', 'CM-6', 'CM-6(a)', 'CM-6(b)', 'CM-7(a)', 'CM-7(b)']
  tag level_bp28: 'intermediary'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv6_conf_default_accept_source_route'
  describe kernel_parameter('net.ipv6.conf.default.accept_source_route') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv6.conf.default.accept_source_route[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-net-ipv6-conf-default-forwarding' do
  impact 0.5
  title 'Disable Kernel Parameter for IPv6 Forwarding by default'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag cis: '3.3.2.2'
  tag level_cis: '1'
  tag ssg: 'sysctl_net_ipv6_conf_default_forwarding'
  describe kernel_parameter('net.ipv6.conf.default.forwarding') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*net.ipv6.conf.default.forwarding[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end

control 'sysctl-user-max_user_namespaces' do
  impact 0.5
  title 'Disable the use of user namespaces'
  tag domain: 'Kernel & network (sysctl)'
  tag evidence: 'effective-runtime'
  tag reboot: 'yes'
  tag ssg: 'sysctl_user_max_user_namespaces'
  describe kernel_parameter('user.max_user_namespaces') do
    its('value') { should cmp 0 }
  end
  describe command("grep -hsE '^[[:space:]]*user.max_user_namespaces[[:space:]]*=[[:space:]]*0([[:space:]]|$)' /etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf 2>/dev/null") do
    its('stdout') { should match(/\S/) }
  end
end
