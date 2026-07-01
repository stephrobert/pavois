#!/usr/bin/env python3
"""Check templates: define the recurring InSpec check patterns ONCE; a control then carries
`template: {name, ...params}` instead of a verbatim check, and the renderer expands it.

Each template is reversible — expand(extract(lines)) == lines — so migration is LOSSLESS: a control
is only converted to a template when the expansion reproduces its check exactly. Params store the
VERBATIM ruby token for the variable parts (e.g. value: "0" or "'root'"), so types round-trip.

Used by tools/gen.py (render expands template -> check) and tools/migrate_templates.py.
"""

import re

# name -> (expand(params)->lines, extract(lines)->params|None)

# sysctl: reboot-proof by construction — assert the LIVE kernel value (kernel_parameter) AND that
# the value is PINNED in a persistent sysctl config file, so it survives a reboot. Without the
# second block a `sysctl -w` (live only) would pass and silently regress on the next boot.
_SYSCTL_PATHS = (
    "/etc/sysctl.conf /etc/sysctl.d/*.conf /run/sysctl.d/*.conf "
    "/usr/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf"
)


def _sysctl_exp(p):
    k, v = p["key"], p["value"]
    vtok = str(v).strip("\"'")
    pat = f"^[[:space:]]*{k}[[:space:]]*=[[:space:]]*{vtok}([[:space:]]|$)"
    paths = _SYSCTL_PATHS
    # kernel.modules_disabled is a one-way switch applied LATE via a systemd oneshot (a boot-time
    # sysctl.d drop-in would lock module loading before /boot/efi mounts -> brick). Its persistent
    # source is then the oneshot's `sysctl -w key=value`, not a sysctl.d file: accept both.
    if k == "kernel.modules_disabled":
        pat = f"{k}[[:space:]]*=[[:space:]]*{vtok}"
        paths = _SYSCTL_PATHS + " /etc/systemd/system/*.service"
    return [
        f"describe kernel_parameter('{k}') do",
        f"  its('value') {{ should cmp {v} }}",
        "end",
        f"describe command(\"grep -hsE '{pat}' {paths} 2>/dev/null\") do",
        "  its('stdout') { should match(/\\S/) }",
        "end",
    ]


def _sysctl_ext(L):
    if len(L) != 6 or L[2] != "end" or L[5] != "end":
        return None
    m1 = re.fullmatch(r"describe kernel_parameter\('([^']+)'\) do", L[0])
    m2 = re.fullmatch(r"  its\('value'\) \{ should cmp (.+) \}", L[1])
    m3 = re.fullmatch(r"describe command\(\"grep -hsE '.*' .*2>/dev/null\"\) do", L[3])
    if m1 and m2 and m3 and L[4] == "  its('stdout') { should match(/\\S/) }":
        return {"name": "sysctl", "key": m1.group(1), "value": m2.group(1)}
    return None


def _pkg_exp(p):
    neg = "" if p["installed"] else "_not"
    return [f"describe package('{p['package']}') do", f"  it {{ should{neg} be_installed }}", "end"]


def _pkg_ext(L):
    if len(L) != 3 or L[2] != "end":
        return None
    m = re.fullmatch(r"describe package\('([^']+)'\) do", L[0])
    m2 = re.fullmatch(r"  it \{ should(_not)? be_installed \}", L[1])
    if m and m2:
        return {"name": "package", "package": m.group(1), "installed": m2.group(1) is None}
    return None


def _owner_exp(p):
    return [
        f"only_if {{ file('{p['path']}').exist? }}",
        f"describe file('{p['path']}') do",
        f"  its('{p['attr']}') {{ should eq {p['value']} }}",
        "end",
    ]


def _owner_ext(L):
    if len(L) != 4 or L[3] != "end":
        return None
    m0 = re.fullmatch(r"only_if \{ file\('([^']+)'\)\.exist\? \}", L[0])
    m1 = re.fullmatch(r"describe file\('([^']+)'\) do", L[1])
    m2 = re.fullmatch(r"  its\('(uid|gid|owner|group)'\) \{ should eq (.+) \}", L[2])
    if m0 and m1 and m2 and m0.group(1) == m1.group(1):
        return {
            "name": "file_owner",
            "path": m1.group(1),
            "attr": m2.group(1),
            "value": m2.group(2),
        }
    return None


def _svc_exp(p):
    return [
        f"describe service('{p['service']}') do",
        "  it { should_not be_enabled }",
        "  it { should_not be_running }",
        "end",
    ]


def _svc_ext(L):
    if len(L) != 4:
        return None
    m = re.fullmatch(r"describe service\('([^']+)'\) do", L[0])
    if (
        m
        and L[1] == "  it { should_not be_enabled }"
        and L[2] == "  it { should_not be_running }"
        and L[3] == "end"
    ):
        return {"name": "service_disabled", "service": m.group(1)}
    return None


# mount_option: reboot-proof by construction — assert the option is on the LIVE mount AND that it
# is PINNED persistently (in /etc/fstab OR a systemd .mount unit), so it survives a reboot. A
# `mount -o remount` (live only) would otherwise pass and silently regress on the next boot.
def _mount_exp(p):
    mp, opt = p["mount_point"], p["option"]
    persist = (
        "{ findmnt --fstab -no OPTIONS " + mp + " 2>/dev/null; "
        "grep -hsE '[[:space:]]" + mp + "[[:space:]]' /etc/fstab 2>/dev/null; "
        "systemctl show -p Options -- $(systemd-escape -p --suffix=mount "
        + mp
        + " 2>/dev/null) 2>/dev/null; } | grep -ow '"
        + opt
        + "'"
    )
    return [
        f"describe mount('{mp}') do",
        f"  its('options') {{ should include '{opt}' }}",
        "end",
        f'describe command("{persist}") do',
        "  its('stdout') { should match(/\\S/) }",
        "end",
    ]


def _mount_ext(L):
    if len(L) != 6 or L[2] != "end" or L[5] != "end":
        return None
    m = re.fullmatch(r"describe mount\('([^']+)'\) do", L[0])
    m2 = re.fullmatch(r"  its\('options'\) \{ should include '([^']+)' \}", L[1])
    m3 = re.fullmatch(r"describe command\(\".*grep -ow '[^']+'\"\) do", L[3])
    if m and m2 and m3 and L[4] == "  its('stdout') { should match(/\\S/) }":
        return {"name": "mount_option", "mount_point": m.group(1), "option": m2.group(1)}
    return None


def _kmod_exp(p):
    return [
        f"describe kernel_module('{p['module']}') do",
        "  it { should_not be_loaded }",
        "  it { should be_disabled }",
        "end",
    ]


def _kmod_ext(L):
    if len(L) != 4:
        return None
    m = re.fullmatch(r"describe kernel_module\('([^']+)'\) do", L[0])
    if (
        m
        and L[1] == "  it { should_not be_loaded }"
        and L[2] == "  it { should be_disabled }"
        and L[3] == "end"
    ):
        return {"name": "kmod_disabled", "module": m.group(1)}
    return None


def _kconfig_exp(p):
    opt = p["option"]
    grep = (
        f"grep -h '^{opt}=' /boot/config-$(uname -r) 2>/dev/null; "
        f"zcat /proc/config.gz 2>/dev/null | grep '^{opt}='"
    )
    neg = "" if p["set"] else "_not"
    return [
        f'describe command("{grep}") do',
        f"  its('stdout') {{ should{neg} match(/^{opt}={p['value']}$/) }}",
        "end",
    ]


def _kconfig_ext(L):
    if len(L) != 3 or L[2] != "end":
        return None
    m0 = re.fullmatch(
        r"""describe command\("grep -h '\^(CONFIG_\w+)=' /boot/config-\$\(uname -r\) """
        r"""2>/dev/null; zcat /proc/config\.gz 2>/dev/null \| grep '\^(CONFIG_\w+)='"\) do""",
        L[0],
    )
    m1 = re.fullmatch(
        r"  its\('stdout'\) \{ should(_not)? match\(/\^(CONFIG_\w+)=(.*?)\$/\) \}", L[1]
    )
    if m0 and m1 and m0.group(1) == m0.group(2) == m1.group(2):
        return {
            "name": "kconfig",
            "option": m1.group(2),
            "value": m1.group(3),
            "set": m1.group(1) is None,
        }
    return None


# cmdline: reboot-proof by construction — assert the param is on the LIVE booted kernel
# (/proc/cmdline) AND pinned in a persistent boot source (grub / kernel cmdline), so it survives
# a reboot. A param injected at boot but absent from grub would otherwise pass and regress.
_GRUB_SRC = (
    "/etc/default/grub /etc/kernel/cmdline /boot/grub/grub.cfg "
    "/boot/grub2/grub.cfg /boot/efi/EFI/*/grub.cfg"
)


# cmdline params that are unsafe or ineffective inside a virtualized guest: the harden
# remediation skips them under systemd-detect-virt, so the check must be N/A there too (else it
# fails forever on a VM). Keep in sync with the remediation gate in go/cmd/harden.go.
_CMDLINE_VIRT_UNSAFE = {"iommu=force"}
_VIRT_ONLY_IF = (
    "only_if('n/a in a virtualized guest: applied only on bare metal') "
    "{ command('systemd-detect-virt -q').exit_status != 0 }"
)


def _cmdline_exp(p):
    tok = p["param"]
    lines = []
    if tok in _CMDLINE_VIRT_UNSAFE:
        lines.append(_VIRT_ONLY_IF)
    lines += [
        "describe command('cat /proc/cmdline') do",
        f"  its('stdout') {{ should match(/(^| ){tok}( |$)/) }}",
        "end",
        f"describe command(\"grep -hwsF '{tok}' {_GRUB_SRC} 2>/dev/null\") do",
        "  its('stdout') { should match(/\\S/) }",
        "end",
    ]
    return lines


def _cmdline_ext(L):
    if L and L[0] == _VIRT_ONLY_IF:  # strip the optional virt guard, re-added by _cmdline_exp
        L = L[1:]
    if (
        len(L) != 6
        or L[2] != "end"
        or L[5] != "end"
        or L[0] != "describe command('cat /proc/cmdline') do"
    ):
        return None
    m = re.fullmatch(r"  its\('stdout'\) \{ should match\(/\(\^\| \)(.+)\( \|\$\)/\) \}", L[1])
    m3 = re.fullmatch(r"describe command\(\"grep -hwsF '.+' .*2>/dev/null\"\) do", L[3])
    if m and m3 and L[4] == "  its('stdout') { should match(/\\S/) }":
        return {"name": "cmdline", "param": m.group(1)}
    return None


# audit_rule: reboot-proof by construction — assert the rule is LOADED live (auditctl -l, matched
# by its key) AND present in the persistent on-disk ruleset (/etc/audit/rules.d, /etc/audit/
# audit.rules). A rule loaded with `auditctl` but absent from disk would regress on reboot.
_AUDIT_RULES = "/etc/audit/rules.d/*.rules /etc/audit/audit.rules"


def _audit_exp(p):
    key = p["key"]  # regex token as authored, e.g. perm_mod, user\-modify or (a|b)
    # Extended-regex (-E) grep so an alternation key like (a|b) is honoured; -F would
    # take the parentheses/pipe literally and never match. For a plain single key -E
    # and -F are equivalent, so single-key controls are unaffected.
    return [
        "describe command('auditctl -l') do",
        f"  its('stdout') {{ should match(/(-k +|key=){key}\\b/) }}",
        "end",
        f"describe command(\"grep -rhwsE '{key}' {_AUDIT_RULES} 2>/dev/null\") do",
        "  its('stdout') { should match(/\\S/) }",
        "end",
    ]


def _audit_ext(L):
    if (
        len(L) != 6
        or L[2] != "end"
        or L[5] != "end"
        or L[0] != "describe command('auditctl -l') do"
    ):
        return None
    m = re.fullmatch(r"  its\('stdout'\) \{ should match\(/\(-k \+\|key=\)(.+)\\b/\) \}", L[1])
    m3 = re.fullmatch(r"describe command\(\"grep -rhwsE '.+' .*2>/dev/null\"\) do", L[3])
    if m and m3 and L[4] == "  its('stdout') { should match(/\\S/) }":
        return {"name": "audit_rule", "key": m.group(1)}
    return None


EXPAND = {
    "sysctl": _sysctl_exp,
    "package": _pkg_exp,
    "file_owner": _owner_exp,
    "kconfig": _kconfig_exp,
    "service_disabled": _svc_exp,
    "mount_option": _mount_exp,
    "kmod_disabled": _kmod_exp,
    "cmdline": _cmdline_exp,
    "audit_rule": _audit_exp,
}
_EXTRACT = [
    _sysctl_ext,
    _pkg_ext,
    _owner_ext,
    _svc_ext,
    _mount_ext,
    _kmod_ext,
    _kconfig_ext,
    _cmdline_ext,
    _audit_ext,
]


def expand(tpl):
    return EXPAND[tpl["name"]](tpl)


def extract(check_lines):
    """Return template params if the check matches a template AND round-trips exactly, else None."""
    for ext in _EXTRACT:
        p = ext(check_lines)
        if p and expand(p) == check_lines:
            return p
    return None
