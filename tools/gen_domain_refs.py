#!/usr/bin/env python3
"""Generate site/src/data/domain-refs.json — per control-domain, the authoritative references that
make a fiche credible: the pavois handbook guide (internal cross-link), the author's hardening guide
on blog.stephane-robert.info (external source + SEO backlink), and the relevant man pages.

Handbook id per domain is read from the handbook content; blog slugs + man pages are curated here
(the blog map includes the guides the author just published — sysctl, mounts, systemd, grub,
kernel-modules, sudoers — which the older handbook cites didn't have). Run after adding a domain or
a new guide. See docs/site-enrichment.md.
"""

import glob
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HANDBOOK = ROOT / "site" / "src" / "content" / "handbook"
OUT = ROOT / "site" / "src" / "data" / "domain-refs.json"

BLOG_BASE = "https://blog.stephane-robert.info/docs/securiser/"
MAN_BASE = "https://manpages.debian.org/"

# domain -> (blog slug under /docs/securiser/, human label). Author-published hardening guides.
BLOG = {
    "SSH": ("durcissement/ssh/", "SSH hardening"),
    "Audit (auditd)": ("durcissement/auditd/", "auditd hardening"),
    "Audit (auditd daemon)": ("durcissement/auditd/", "auditd hardening"),
    "Accounts (PAM modules)": ("durcissement/pam/", "PAM hardening"),
    "File permissions": ("durcissement/acl/", "Permissions & ACL"),
    "File ownership": ("durcissement/acl/", "Permissions & ACL"),
    "Sudo": ("durcissement/sudoers/", "sudo hardening & logging"),
    "Kernel & network (sysctl)": ("durcissement/sysctl/", "sysctl kernel hardening"),
    "Mounts": ("durcissement/mounts/", "Mount point hardening"),
    "systemd services": ("durcissement/systemd/", "systemd service sandboxing"),
    "Bootloader (grub)": ("durcissement/grub/", "GRUB password protection"),
    "Kernel command line": ("durcissement/grub/", "GRUB & kernel cmdline"),
    "Kernel modules": ("durcissement/kernel-modules/", "Disabling kernel modules"),
    "Firewall": ("reseaux/firewalld/", "Host firewall (firewalld/ufw)"),
    "Logging (journald)": ("socle/referentiel/cloud/journalisation-audit/", "Logging & audit"),
    "Logging": ("socle/referentiel/cloud/journalisation-audit/", "Logging & audit"),
    "Time synchronization": ("services/reseau/chrony/", "Time sync (chrony)"),
    "Packages": ("supply-chain/securiser-dependances/", "Securing dependencies"),
}

# domain -> man pages (manpages.debian.org). The config/tool that owns the effective state.
MAN = {
    "SSH": ["sshd_config"],
    "Kernel & network (sysctl)": ["sysctl.conf", "sysctl"],
    "Audit (auditd)": ["auditctl", "auditd"],
    "Audit (auditd daemon)": ["auditd.conf"],
    "Sudo": ["sudoers"],
    "Accounts (PAM modules)": ["pam.conf"],
    "Accounts (login.defs)": ["login.defs"],
    "Accounts (faillock)": ["faillock.conf"],
    "Passwords (pwquality)": ["pwquality.conf"],
    "systemd services": ["systemd.exec"],
    "Mounts": ["fstab"],
    "Kernel modules": ["modprobe.d"],
    "Cron/at access control": ["crontab"],
}


def main():
    handbook_by_domain = {}
    for f in glob.glob(str(HANDBOOK / "*.json")):
        d = json.loads(Path(f).read_text(encoding="utf-8"))
        if d.get("domain"):
            handbook_by_domain[d["domain"]] = {"id": d["id"], "title": d.get("title", {})}

    domains = set(BLOG) | set(MAN) | set(handbook_by_domain)
    out = {}
    for dom in sorted(domains):
        entry = {}
        if dom in handbook_by_domain:
            entry["handbook"] = handbook_by_domain[dom]
        if dom in BLOG:
            slug, label = BLOG[dom]
            entry["blog"] = {"url": BLOG_BASE + slug, "label": label}
        if dom in MAN:
            entry["man"] = [{"page": p, "url": MAN_BASE + p} for p in MAN[dom]]
        out[dom] = entry

    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"domain-refs: {len(out)} domains -> {OUT.relative_to(ROOT)} "
        f"({sum('blog' in v for v in out.values())} blog, "
        f"{sum('handbook' in v for v in out.values())} handbook, "
        f"{sum('man' in v for v in out.values())} man)"
    )


if __name__ == "__main__":
    main()
