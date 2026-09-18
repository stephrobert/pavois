#!/usr/bin/env python3
"""FAIL when a control would report a deviation on a host that satisfies its requirement.

Every lint in this repository asks whether a control is well formed (lint_rules), runs with the
privilege it needs (lint_shell_first_word) or agrees with its neighbours (lint_contradictions).
None of them asks whether the control demands MORE than the norm it maps to, or demands something
a compliant host may legitimately not have. Users find those, one scan at a time. Four are in the
tree today:

    findloop-file-groupownership-system-commands-dirs
        title:  "group owned by root or a system account"
        check:  find ... -type f ! -group root      (unix_chkpwd is root:shadow on every Debian)
    banner-motd
        check:  file('/etc/motd') content should match /\\S/, with no only_if
        CIS 1.7.1: "If the motd is not used, this file can be removed" (RHEL ships it empty,
        Ubuntu does not ship it at all)
    firewall-default-deny
        check:  nft list ruleset | grep 'hook input.*policy drop' || iptables -S INPUT ...
        remediation: choose ufw | nftables | firewalld. firewalld's input chain is `policy accept`
        with a terminal reject: a stock RHEL that denies by default fails
    ssh-set-login-grace-time
        check:  /^logingracetime\\s+60$/            CIS: 1 to 60, so a host at 30 fails

An invented deviation is worse than a missed one: it teaches the operator to distrust the green
results too. Seven signatures, each mechanical, each grounded in a control of the tree:

  S1 optional-artefact    a positive, unguarded assertion on an artefact the norm declares
                          optional (OPTIONAL), or on a package the control itself names in
                          `requires_package` while no norm-mapped `package` control mandates it
  S2 or-title             the title says "root OR a system account", the check demands one value
  S3 family-token         a Debian-only or RHEL-only token in the check resolved for the OTHER
                          family, unguarded, expecting a positive result
  S4 choose-unaudited     the `choose` remediation offers options the check never looks at
  S5 dropin-blind         the check reads ONE file where the norm accepts several, or where the
                          service also reads a drop-in directory (DROPIN); template path lists too
  S6 exact-where-bound    an exact number in an `sshd -T` regex where the norm gives a bound
  S7 service-if-installed a service demanded enabled+running with no guard where the norm says
                          "IF installed" (IF_INSTALLED), or with no norm mapped at all

The golden baselines cannot see this class: those hosts are hardened BY pavois, which writes the
artefact or the exact value. The false positive only shows on a host hardened by someone else,
which is exactly what a user reports. Reads the REFERENCE (rules.yml), resolved per OS the way
gen.py renders it: the defect lives in the reference, not in the rendered corpus.

Usage: python3 tools/false_positives.py [--json] [--explain]   (--selftest proves it bites)
"""

from __future__ import annotations

import copy
import json
import pathlib
import re
import sys
from collections.abc import Iterator
from dataclasses import asdict, dataclass
from typing import Any

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import gen  # noqa: E402  (per-OS resolution of @os blocks and @{primitives}, as the render does)
import templates  # noqa: E402  (a templated check is still a check: expand it before reading)

RULES = ROOT / "docs" / "reference" / "rules.yml"

DEB = {"debian12", "debian13", "ubuntu2204", "ubuntu2404", "ubuntu2604"}

# (signature, control id) -> why the finding is understood and deliberately kept. A reason is
# mandatory: an exception with no reason is how a guard stops meaning anything.
ACCEPTED: dict[tuple[str, str], str] = {
    ("S1", "posture-process-accounting"): (
        "pavois-own posture control: the requirement is pavois's, there is no norm to be "
        "stricter than, and the operator opts into the posture family knowingly"
    ),
    ("S7", "posture-process-accounting"): "same posture control, seen through the service rule",
    ("S1", "posture-sysstat"): "pavois-own posture control, same reason",
    ("S7", "growth-tmp-cleaned"): (
        "pavois-own growth control: bounding /tmp is pavois's requirement, documented as such"
    ),
}

# What the tree carried the day this linter landed, with the issue that tracks it. A backlog entry
# is NOT an exception: it is a defect somebody has read and written down, and the list may only
# shrink. The difference matters, and the tool enforces both halves: a NEW finding fails the build,
# and a backlog entry that stops firing fails it too, so the list cannot quietly rot into fiction.
BACKLOG: dict[tuple[str, str], str] = {
    ("S1", "banner-motd"): "#321",
    ("S1", "file-at-allow-exists"): "#321",
    ("S1", "file-cron-allow-exists"): "#321",
    ("S2", "findloop-file-groupownership-system-commands-dirs"): "#321, and #183",
    ("S3", "misc-accounts-tmout"): "#321",
    ("S4", "firewall-default-deny"): "#321",
    ("S5", "<template sysctl>"): "#321",
    ("S5", "umask-etc-bashrc"): "#321",
    ("S6", "ssh-set-idle-timeout"): "#321",
    ("S6", "ssh-set-login-grace-time"): "#321",
    ("S6", "ssh-set-maxstartups"): "#321",
    ("S7", "service-cron-enabled"): "#321",
    ("S7", "service-crond-enabled"): "#321",
    ("S7", "service-fapolicyd-enabled"): "#321",
    ("S7", "service-rngd-enabled"): "#321",
    ("S7", "service-usbguard-enabled"): "#321",
}

EXPLAIN = {
    "S1": "optional artefact asserted without a guard: a compliant host may not have it",
    "S2": "the title allows several values, the check demands exactly one",
    "S3": "a token of one distro family inside the check resolved for the other family",
    "S4": "the `choose` remediation offers options the check does not audit",
    "S5": "one file read where the norm or the service accepts several locations",
    "S6": "an exact number where the norm gives a bound: a stricter host fails",
    "S7": "a service demanded active with no `if installed` guard, or with no norm behind it",
}

# S1: artefacts a compliant host may not have, with the norm sentence that says so. Prefix match.
OPTIONAL: dict[str, str] = {
    "/etc/motd": "CIS 1.7.1: 'If the motd is not used, this file can be removed'",
    "/etc/cron": "CIS 2.4.1.x: 'IF cron is installed'",
    "/etc/crontab": "CIS 2.4.1.2: 'IF cron is installed'",
    "/etc/at.": "CIS 2.4.2.1: 'IF at is installed'",
    "/etc/dconf": "CIS 1.8.x: 'IF GDM is installed'",
    "/etc/gdm": "CIS 1.8.x: 'IF GDM is installed'",
    "/var/log/gdm": "CIS 6.2.4.1 names gdm logs as a special case, only where present",
    "/etc/postfix": "no mapped norm mandates an MTA",
    "/etc/sssd": "SSSD is site-dependent (the guard-asymmetry case of lint_rules)",
    "/etc/chrony": "exclusivity.yml time-sync: chrony is one option among several",
    "/etc/ntp": "exclusivity.yml time-sync: ntp is one option among several",
    "/etc/rsyslog": "exclusivity.yml logging: rsyslog is one option among several",
    "/etc/usbguard": "STIG-only component",
    "/etc/fapolicyd": "STIG-only component",
    "/etc/aide": "the norms mandate AN integrity tool, not aide",
    "/etc/securetty": "gone from Debian >= 11 (pam_securetty is no longer used)",
}

# S3: (RHEL-only token, Debian-only token). A check that names both is portable and is skipped.
PAIRS: list[tuple[str, str]] = [
    (r"/etc/bashrc\b", r"/etc/bash\.bashrc"),
    (r"/var/log/messages", r"/var/log/syslog"),
    (r"/var/log/secure\b", r"/var/log/auth\.log"),
    (r"pam\.d/(system|password)-auth", r"pam\.d/common-"),
    (
        r"(?<![\w-])sshd\.service|service\('sshd'\)|is-(active|enabled) (--quiet )?sshd\b",
        r"(?<![\w-])ssh\.service|service\('ssh'\)|is-(active|enabled) (--quiet )?ssh\b",
    ),
    (r"(?<![\w-])crond\b", r"(?<![\w-])cron\.service|service\('cron'\)"),
    (r"(?<![\w-])chronyd\b", r"(?<![\w-])chrony\b"),
    (r"/boot/grub2\b|grub2-", r"/boot/grub/"),
    (r"(?<![\w-])(dnf|yum|rpm)(?![\w-])", r"(?<![\w-])(apt|apt-get|dpkg|dpkg-query)(?![\w-])"),
    (r"(?<![\w-])authselect\b", r"pam-auth-update"),
    (r"(?<!/usr)/sbin/nologin", r"/usr/sbin/nologin"),
    (
        r"(?<![\w-])(selinux|getenforce|sestatus|semanage)\b",
        r"(?<![\w-])(apparmor|aa-status|apparmor_parser)\b",
    ),
    (r"(?<![\w-])httpd\b", r"(?<![\w-])apache2\b"),
    (r"(?<![\w-])gdm\b(?!3)", r"(?<![\w-])gdm3\b"),
    (r"/etc/sysconfig/", r"/etc/default/(?!grub|useradd)"),
]

# S4: the command a technology answers to, when its package or service name is not in the check.
CHOICE_CLI = {
    "nftables": "nft",
    "firewalld": "firewall-cmd",
    "ufw": "ufw",
    "chrony": "chronyc",
    "timesyncd": "timedatectl",
}

# S5: main file -> the other locations the norm or the service reads. A check that reads the
# main file for CONTENT and none of the alternatives fails a host configured in one of them.
DROPIN: dict[str, list[str]] = {
    "/etc/ssh/sshd_config": ["sshd_config.d", "sshd -T"],
    "/etc/security/pwquality.conf": ["pwquality.conf.d"],
    "/etc/systemd/journald.conf": ["journald.conf.d"],
    "/etc/security/limits.conf": ["limits.d"],
    "/etc/rsyslog.conf": ["rsyslog.d"],
    "/etc/systemd/coredump.conf": ["coredump.conf.d"],
    "/etc/systemd/system.conf": ["system.conf.d"],
    "/etc/systemd/logind.conf": ["logind.conf.d"],
    "/etc/sudoers": ["sudoers.d"],
    "/etc/sysctl.conf": ["sysctl.d"],
    "/etc/logrotate.conf": ["logrotate.d"],
    "/etc/profile": ["profile.d"],
    "/etc/bash.bashrc": ["profile.d", "/etc/profile"],
    "/etc/bashrc": ["profile.d", "/etc/profile"],
    "/etc/chrony/chrony.conf": ["conf.d", "sources.d"],
    "/etc/chrony.conf": ["conf.d", "sources.d"],
    "/etc/tmpfiles.d": ["/usr/lib/tmpfiles.d"],
}

# S5, template level: the persistence path lists a template greps, and what they must contain.
# One omission here is inherited by every control of the template, so it is reported ONCE.
TEMPLATE_PATHS: dict[str, tuple[str, list[str]]] = {
    "_SYSCTL_PATHS": (
        "sysctl",
        [
            "/etc/sysctl.conf",
            "/etc/sysctl.d/*.conf",
            "/run/sysctl.d/*.conf",
            "/usr/local/lib/sysctl.d/*.conf",
            "/usr/lib/sysctl.d/*.conf",
            "/lib/sysctl.d/*.conf",
        ],
    ),
    "_AUDIT_RULES": ("audit_rule", ["/etc/audit/rules.d/*.rules", "/etc/audit/audit.rules"]),
    "_GRUB_SRC": (
        "cmdline",
        [
            "/etc/default/grub",
            "/etc/kernel/cmdline",
            "/boot/grub/grub.cfg",
            "/boot/grub2/grub.cfg",
            "/boot/efi/EFI/*/grub.cfg",
        ],
    ),
}

# S6: sshd directives the norms BOUND. An exact value in the check makes a stricter host fail.
# `randomize_va_space = 2` is exact by nature and is not here: this is a list, not a regex.
BOUNDED: dict[str, str] = {
    "logingracetime": "CIS 5.1.x: 1 to 60",
    "clientaliveinterval": "CIS 5.1.x: greater than zero (STIG: 600 or less)",
    "clientalivecountmax": "CIS 5.1.x: greater than zero",
    "maxauthtries": "CIS 5.1.x: 4 or less",
    "maxsessions": "CIS 5.1.x: 10 or less",
    "maxstartups": "CIS 5.1.x: 10:30:60 or more restrictive",
}

# S7: services the norm demands only where the package is installed. Unit suffix stripped.
IF_INSTALLED: dict[str, str] = {
    "cron": "CIS 2.4.1.1: 'IF cron is installed'",
    "crond": "CIS 2.4.1.1: 'IF cron is installed'",
}


@dataclass
class Finding:
    sig: str
    cid: str
    os: str
    evidence: str
    why: str


# ----------------------------------------------------------------------------- reading a control

POSITIVE = re.compile(
    r"should eq 'ok'|should match\(/\\S/\)|should exist|its\('content'\)|be_file"
    r"|should eq 'active'|should eq 'enabled'|should be_enabled|should be_running"
)
# `... || echo ko` is the failure branch; a `||` anywhere else offers an ALTERNATIVE source,
# and the absence of one of them is not a failure.
ALTERNATIVE = re.compile(r"\|\|(?!\s*echo ko)")
# Possessive (`*+`), and the reason is a CodeQL finding rather than taste: with a greedy `*` this
# alternation backtracks exponentially on `command("` followed by repeated `\\a`, measured at
# 2.8 ms, 42 ms then 654 ms for 14, 18 and 22 repetitions. Nothing is lost: at each position the
# parse is unambiguous (a backslash starts an escape, anything else is one character), so no
# backtracking was ever needed to find the closing quote.
CMD_RE = re.compile(r"command\(\s*(['\"])((?:\\.|(?!\1).)*+)\1")
PATH_RE = re.compile(r"(/(?:etc|var|usr|boot|opt|srv|home|root)/[\w./*@{}+-]+)")
WORD_START = re.compile(
    r"(?:^|[|;&({]\s*|\$\(\s*|do\s+|then\s+|else\s+|!\s+)\s*"
    r"(?:sudo\s+|timeout\s+\d+\s+|env\s+)?([A-Za-z][\w.+-]*)"
)


def load(path: pathlib.Path) -> dict[str, Any]:
    d = yaml.safe_load(path.read_text(encoding="utf-8"))
    return d.get("controls", d)


def controls(rules: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {k: v for k, v in rules.items() if isinstance(v, dict) and "applicable_os" in v}


def pick(e: dict[str, Any], cid: str, field: str, os: str) -> Any:
    """The field as gen.py renders it for `os`: @os block resolved, @{primitives} substituted.

    An unknown primitive is a hard error for the render and stops it; here it only means the
    token stays literal, which is enough to read the check.
    """
    v = gen.pick(e.get(field), os)
    try:
        return gen.subst(v, os, cid)
    except SystemExit:
        return v


def template(e: dict[str, Any], cid: str, os: str) -> dict[str, Any] | None:
    t = pick(e, cid, "template", os)
    return t if isinstance(t, dict) and t.get("name") in templates.EXPAND else None


def check_text(e: dict[str, Any], cid: str, os: str) -> str:
    t = template(e, cid, os)
    if t:
        return "\n".join(templates.expand(t))
    c = pick(e, cid, "check", os)
    lines = c if isinstance(c, list) else ([str(c)] if c else [])
    return "\n".join(str(x) for x in lines)


def per_os(e: dict[str, Any], cid: str) -> Iterator[tuple[str, str, Any]]:
    for os in e.get("applicable_os") or []:
        yield os, check_text(e, cid, os), pick(e, cid, "remediation", os)


def title_of(e: dict[str, Any]) -> str:
    t = e.get("title")
    if isinstance(t, dict) and "@os" in t:
        return " | ".join(str(x) for x in t["@os"].values())
    return str(t or "")


def positive(txt: str) -> bool:
    """The check FAILS when the thing is absent (as opposed to `... && echo ko`)."""
    return bool(POSITIVE.search(txt)) and "&& echo ko" not in txt


def guarded(txt: str) -> bool:
    return "only_if" in txt


def scripts(txt: str) -> list[str]:
    return [m.group(2) for m in CMD_RE.finditer(txt)]


def has_norm(e: dict[str, Any]) -> bool:
    return bool(e.get("norms"))


def fam(os: str) -> str:
    return "deb" if os in DEB else "rhel"


# ----------------------------------------------------------------------------- the signatures


def s1_optional_artefact(ctrls: dict[str, dict[str, Any]]) -> list[Finding]:
    out: list[Finding] = []
    # A package is mandated when a norm-mapped `package` control asserts it installed.
    mandated: dict[str, str] = {}
    for cid, e in ctrls.items():
        if not has_norm(e):
            continue
        for os in e["applicable_os"]:
            t = template(e, cid, os)
            if t and t["name"] == "package" and t.get("installed"):
                mandated[str(t.get("package"))] = cid
    for cid, e in ctrls.items():
        seen: set[str] = set()
        for os, txt, _ in per_os(e, cid):
            if guarded(txt) or not positive(txt) or ALTERNATIVE.search(txt):
                continue
            for p in sorted(set(PATH_RE.findall(txt))):
                for prefix, why in OPTIONAL.items():
                    if p.startswith(prefix) and prefix not in seen:
                        seen.add(prefix)
                        out.append(Finding("S1", cid, os, f"asserts on {p} with no only_if", why))
            pkg = str(pick(e, cid, "requires_package", os) or "")
            if pkg and pkg not in mandated and "pkg" not in seen:
                seen.add("pkg")
                out.append(
                    Finding(
                        "S1",
                        cid,
                        os,
                        f"requires_package: {pkg}, check asserts positively with no only_if",
                        "no norm-mapped `package` control mandates it: a compliant host may "
                        "not have it, and harden installs it to satisfy this very control",
                    )
                )
    return out


OR_TITLE = re.compile(
    r"\bor (a |an )?(system|service|application) (account|group|user)|\bor root\b|root or\b"
    r"|or more restrictive|or stricter|or less permissive",
    re.I,
)
SINGLE = re.compile(
    r"! -group root(?! !)|! -user root(?! !)|should eq 'root'|should eq 0\b"
    r"|its\('gid'\) \{ should eq 0|its\('uid'\) \{ should eq 0"
)


def s2_or_title(ctrls: dict[str, dict[str, Any]]) -> list[Finding]:
    out: list[Finding] = []
    for cid, e in ctrls.items():
        t = title_of(e) + " " + str(e.get("note") or "")
        if not OR_TITLE.search(t):
            continue
        for os, txt, _ in per_os(e, cid):
            m = SINGLE.search(txt)
            if m and "-o " not in txt:
                out.append(
                    Finding(
                        "S2",
                        cid,
                        os,
                        f"title {title_of(e)[:60]!r}, check {m.group(0)!r}",
                        "the title allows an alternative the check refuses",
                    )
                )
                break
    return out


def s3_family_token(ctrls: dict[str, dict[str, Any]]) -> list[Finding]:
    out: list[Finding] = []
    for cid, e in ctrls.items():
        seen: set[str] = set()
        for os, txt, _ in per_os(e, cid):
            if guarded(txt) or not positive(txt):
                continue
            for rhel_re, deb_re in PAIRS:
                r_in, d_in = re.search(rhel_re, txt), re.search(deb_re, txt)
                if fam(os) == "deb" and r_in and not d_in and rhel_re not in seen:
                    seen.add(rhel_re)
                    out.append(
                        Finding(
                            "S3",
                            cid,
                            os,
                            f"RHEL token {r_in.group(0)!r} in a Debian-family check",
                            "the file, service or tool does not exist there under that name",
                        )
                    )
                if fam(os) == "rhel" and d_in and not r_in and deb_re not in seen:
                    seen.add(deb_re)
                    out.append(
                        Finding(
                            "S3",
                            cid,
                            os,
                            f"Debian token {d_in.group(0)!r} in a RHEL-family check",
                            "the file, service or tool does not exist there under that name",
                        )
                    )
    return out


def s4_choose_unaudited(ctrls: dict[str, dict[str, Any]]) -> list[Finding]:
    out: list[Finding] = []
    for cid, e in ctrls.items():
        for os, txt, rem in per_os(e, cid):
            if not isinstance(rem, dict) or rem.get("resource") != "choose":
                continue
            options = rem.get("options") or {}
            missing = []
            for opt, spec in options.items():
                names = {opt}
                if isinstance(spec, dict):
                    names |= {str(spec.get("service") or ""), str(spec.get("package") or "")}
                if opt in CHOICE_CLI:
                    names.add(CHOICE_CLI[opt])
                names.discard("")
                pat = r"(?<![\w-])(" + "|".join(re.escape(n) for n in sorted(names)) + r")(?![\w-])"
                if not re.search(pat, txt):
                    missing.append(opt)
            if missing:
                out.append(
                    Finding(
                        "S4",
                        cid,
                        os,
                        f"remediation offers {sorted(options)}, check never mentions {missing}",
                        "a host that chose one of those satisfies the requirement and fails",
                    )
                )
            break
    return out


CONTENT_READ = re.compile(r"grep|its\('content'\)|parse_config|login_defs|\bcat\b|awk|sed")


def s5_dropin_blind(ctrls: dict[str, dict[str, Any]]) -> list[Finding]:
    out: list[Finding] = []
    for cid, e in ctrls.items():
        seen: set[str] = set()
        for os, txt, _ in per_os(e, cid):
            if template(e, cid, os) or not CONTENT_READ.search(txt):
                continue
            for main, alts in DROPIN.items():
                if main not in txt or main in seen:
                    continue
                read = re.search(r"(grep|cat|awk|sed|parse_config)[^\n]*" + re.escape(main), txt)
                content = re.search(re.escape(main) + r"'\) do\n\s*its\('content", txt)
                if not (read or content) or any(a in txt for a in alts):
                    continue
                seen.add(main)
                out.append(
                    Finding(
                        "S5",
                        cid,
                        os,
                        f"reads {main} and none of {alts}",
                        "the same setting placed in an accepted alternative location fails",
                    )
                )
    for attr, (tname, required) in TEMPLATE_PATHS.items():
        have = getattr(templates, attr, "")
        missing = [p for p in required if p not in have]
        if missing:
            n = sum(
                1
                for cid, e in ctrls.items()
                if any(
                    (template(e, cid, os) or {}).get("name") == tname for os in e["applicable_os"]
                )
            )
            out.append(
                Finding(
                    "S5",
                    f"<template {tname}>",
                    "*",
                    f"templates.{attr} omits {missing}",
                    f"a value persisted there fails the persistence half; {n} controls inherit it",
                )
            )
    return out


EXACT_SSHD = re.compile(r"match\(/\^(\w+)\\s\+(\d+(?::\d+:\d+)?)\$/i?\)")


def s6_exact_where_bound(ctrls: dict[str, dict[str, Any]]) -> list[Finding]:
    out: list[Finding] = []
    for cid, e in ctrls.items():
        for os, txt, _ in per_os(e, cid):
            if template(e, cid, os):
                continue
            for m in EXACT_SSHD.finditer(txt):
                directive = m.group(1).lower()
                if directive in BOUNDED:
                    out.append(
                        Finding(
                            "S6",
                            cid,
                            os,
                            f"{m.group(0)} demands exactly {m.group(2)}",
                            BOUNDED[directive] + ": a stricter value satisfies the norm and fails",
                        )
                    )
                    break
            else:
                continue
            break
    return out


ACTIVE = re.compile(
    r"is-(?:active|enabled) (?:--quiet )?([\w@.-]+)"
    r"|service\('([^']+)'\) do\n\s*it \{ should be_(?:running|enabled)"
)


def s7_service_if_installed(ctrls: dict[str, dict[str, Any]]) -> list[Finding]:
    out: list[Finding] = []
    for cid, e in ctrls.items():
        if e.get("exclusive_group"):
            continue
        for os, txt, _ in per_os(e, cid):
            if guarded(txt) or "for s in" in txt or ALTERNATIVE.search(txt):
                continue
            if not positive(txt):
                continue
            for m in ACTIVE.finditer(txt):
                unit = (m.group(1) or m.group(2)).replace(".service", "")
                if unit in IF_INSTALLED:
                    why = IF_INSTALLED[unit]
                elif not has_norm(e):
                    why = "no norm mapped: whose requirement is this, and on which hosts?"
                else:
                    continue
                out.append(Finding("S7", cid, os, f"demands {unit} active with no only_if", why))
                break
            else:
                continue
            break
    return out


SIGNATURES = [
    s1_optional_artefact,
    s2_or_title,
    s3_family_token,
    s4_choose_unaudited,
    s5_dropin_blind,
    s6_exact_where_bound,
    s7_service_if_installed,
]


def find(rules: dict[str, Any]) -> list[Finding]:
    """One finding per (signature, control): the first OS that shows it speaks for the others."""
    ctrls = controls(rules)
    out: list[Finding] = []
    seen: set[tuple[str, str]] = set()
    for sig in SIGNATURES:
        for f in sig(ctrls):
            if (f.sig, f.cid) not in seen:
                seen.add((f.sig, f.cid))
                out.append(f)
    return sorted(out, key=lambda f: (f.sig, f.cid))


# ----------------------------------------------------------------------------- selftest

BASE = {"applicable_os": ["debian12"], "severity": "medium", "impact": 0.5, "title": "test"}


def plants() -> list[tuple[str, str, dict[str, Any], dict[str, Any]]]:
    """(signature, id, the defective control, the same control made correct)."""
    motd = ["describe file('/etc/motd') do", "  its('content') { should match(/\\S/) }", "end"]
    tool = [
        "describe command('zz-tool --status') do",
        "  its('stdout.strip') { should eq 'ok' }",
        "end",
    ]
    bins = [
        "describe command('find /usr/bin -type f ! -group root 2>/dev/null') do",
        "  its('stdout.strip') { should eq '' }",
        "end",
    ]
    bins_ok = [bins[0].replace("! -group root", "! -group root ! -group daemon"), *bins[1:]]
    msgs = [
        "describe command('grep -q zz /var/log/messages && echo ok || echo ko') do",
        "  its('stdout.strip') { should eq 'ok' }",
        "end",
    ]
    msgs_ok = [msgs[0].replace("/var/log/messages", "/var/log/messages /var/log/syslog"), *msgs[1:]]
    loop = 'for s in zz-a; do systemctl is-active --quiet "$s" && echo ok; done'
    choose = [
        "describe command('" + loop + "') do",
        "  its('stdout.strip') { should eq 'ok' }",
        "end",
    ]
    choose_ok = [choose[0].replace("zz-a;", "zz-a zz-b;"), *choose[1:]]
    pwq = [
        "describe command('grep -qE zz /etc/security/pwquality.conf && echo ok || echo ko') do",
        "  its('stdout.strip') { should eq 'ok' }",
        "end",
    ]
    pwq_ok = [
        pwq[0].replace(
            "/etc/security/pwquality.conf",
            "/etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf",
        ),
        *pwq[1:],
    ]
    grace = [
        "describe command('sshd -T') do",
        "  its('stdout') { should match(/^logingracetime\\s+60$/i) }",
        "end",
    ]
    grace_ok = [grace[0], grace[1].replace("60$", "([1-9]|[1-5][0-9]|60)$"), grace[2]]
    cron = [
        "describe service('cron.service') do",
        "  it { should be_enabled }",
        "  it { should be_running }",
        "end",
    ]
    guard_cron = "only_if { package('cron').installed? }"
    choose_rem = {
        "resource": "choose",
        "default": "zz-a",
        "options": {"zz-a": {"service": "zz-a"}, "zz-b": {"service": "zz-b"}},
    }
    return [
        (
            "S1",
            "zz-test-optional-file",
            {**BASE, "check": motd},
            {**BASE, "check": ["only_if { file('/etc/motd').exist? }", *motd]},
        ),
        (
            "S1",
            "zz-test-optional-package",
            {**BASE, "check": tool, "requires_package": "zz-fictional-pkg"},
            {
                **BASE,
                "check": ["only_if { package('zz-fictional-pkg').installed? }", *tool],
                "requires_package": "zz-fictional-pkg",
            },
        ),
        (
            "S2",
            "zz-test-or-title",
            {**BASE, "title": "group owned by root or a system account", "check": bins},
            {**BASE, "title": "group owned by root or a system account", "check": bins_ok},
        ),
        (
            "S3",
            "zz-test-family-token",
            {**BASE, "applicable_os": ["debian12", "rhel9"], "check": msgs},
            {**BASE, "applicable_os": ["debian12", "rhel9"], "check": msgs_ok},
        ),
        (
            "S4",
            "zz-test-choose",
            {**BASE, "check": choose, "remediation": choose_rem},
            {**BASE, "check": choose_ok, "remediation": choose_rem},
        ),
        ("S5", "zz-test-dropin", {**BASE, "check": pwq}, {**BASE, "check": pwq_ok}),
        ("S6", "zz-test-exact", {**BASE, "check": grace}, {**BASE, "check": grace_ok}),
        (
            "S7",
            "zz-test-service",
            {**BASE, "check": cron, "norms": {"cis": "2.4.1.1"}},
            {**BASE, "check": [guard_cron, *cron], "norms": {"cis": "2.4.1.1"}},
        ),
    ]


def selftest() -> int:
    """Plant one defective control per signature and demand red; plant its witness and demand
    green. A guard that cries on the witness proves nothing, so both halves are required."""
    rules = load(RULES)
    if len(controls(rules)) < 100:
        print("selftest: rules.yml parsed to fewer than 100 controls, the reader is broken")
        return 1
    ok = True
    bad = copy.deepcopy(rules)
    for _, cid, defective, _witness in plants():
        bad[cid] = defective
    hits = {(f.sig, f.cid) for f in find(bad)}
    print("the false-positive linter rejects:")
    for sig, cid, _, _ in plants():
        if (sig, cid) in hits:
            print(f"  ok   {sig} {cid}")
        else:
            print(f"  FAIL {sig} {cid}: the planted defect was not caught")
            ok = False
    good = copy.deepcopy(rules)
    for _, cid, _defective, witness in plants():
        good[cid] = witness
    leaks = [f for f in find(good) if f.cid.startswith("zz-test-")]
    print("and keeps quiet on the witnesses:")
    if leaks:
        for f in leaks:
            print(f"  FAIL {f.sig} {f.cid}: cried on the corrected control ({f.evidence})")
        ok = False
    else:
        print(f"  ok   {len(plants())} corrected controls, no finding")
    return 0 if ok else 1


# ----------------------------------------------------------------------------- main


def main() -> int:
    if not RULES.exists():
        print(f"missing {RULES.relative_to(ROOT)}")
        return 1
    if "--selftest" in sys.argv[1:]:
        return selftest()
    if "--explain" in sys.argv[1:]:
        print(__doc__.strip())
        return 0

    rules = load(RULES)
    n = len(controls(rules))
    # An empty read is not a clean tree: a renamed key or a moved file makes every signature
    # return nothing, and this would announce success having examined no control at all.
    if n < 100:
        print(f"false-positives: only {n} control(s) parsed from rules.yml")
        print("That is not a clean tree, it is a reader that stopped reading. Check the schema.")
        return 1

    found = find(rules)
    kept = [f for f in found if (f.sig, f.cid) not in ACCEPTED and (f.sig, f.cid) not in BACKLOG]
    accepted = [f for f in found if (f.sig, f.cid) in ACCEPTED]
    known = [f for f in found if (f.sig, f.cid) in BACKLOG]
    # A backlog entry that no longer fires has been FIXED, and leaving it listed would let the
    # next real finding hide behind it. The list may only shrink, and only on purpose.
    stale = sorted(set(BACKLOG) - {(f.sig, f.cid) for f in found})

    if "--json" in sys.argv[1:]:
        print(
            json.dumps(
                {
                    "findings": [asdict(f) for f in kept],
                    "known": [asdict(f) for f in known],
                    "accepted": [asdict(f) for f in accepted],
                    "stale_backlog": [list(k) for k in stale],
                },
                indent=2,
            )
        )
        return 1 if kept or stale else 0

    if kept:
        print(
            f"false-positives: {len(kept)} control(s) would FAIL on a host that satisfies "
            "the requirement\n"
        )
        for f in kept:
            print(f"  {f.sig} {f.cid} [{f.os}]")
            print(f"       {f.evidence}")
            print(f"       {f.why}")
        print()
        print("Each one needs a decision, not a tweak: a guard (only_if on the artefact or the")
        print("package), an @os key, a bound instead of a value, an audit of every option, or an")
        print("entry in ACCEPTED with the reason recorded.")
    if known:
        print(f"\nknown, tracked, and allowed to shrink only ({len(known)}):")
        for f in known:
            print(f"  {f.sig} {f.cid} [{f.os}]: {BACKLOG[(f.sig, f.cid)]}")
    if stale:
        print(f"\n{len(stale)} backlog entry(ies) no longer fire: they were FIXED.")
        for sig, cid in stale:
            print(f"  {sig} {cid}: remove it from BACKLOG, the list may only shrink")
    if accepted:
        print(f"\naccepted with a reason ({len(accepted)}):")
        for f in accepted:
            print(f"  {f.sig} {f.cid}: {ACCEPTED[(f.sig, f.cid)]}")
    if not kept and not stale:
        print(f"\nfalse-positives: {n} control(s) read, no NEW control demands more than its norm")
        print("  or an artefact a compliant host may lack")
    return 1 if kept or stale else 0


if __name__ == "__main__":
    sys.exit(main())
