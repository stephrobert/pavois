# pavois docs — organization & roadmap

## 1. Content organization (information architecture)

The pavois site has five content areas:

| Area | URL | What it is | Status |
|---|---|---|---|
| **Rules** | `/rules/<id>/` | 776 bilingual rule fiches (effective-config check, norms, harden remediation, verify, logs, impact) | ✅ done |
| **Standards** | `/standards/<norm>/` | filterable table per standard (CIS / ANSSI / NIST / PCI / STIG) + version | ✅ done |
| **Glossary** | `/glossary/` | 191 bilingual terms (A–Z, filterable) | ✅ done |
| **Docs (CLI)** | `/docs/` | pavois user docs: commands, options, workflow, examples | ✅ done |
| **Handbook** | `/handbook/<id>/` | the hardening knowledge base — threats → principles → per-topic → tooling | 🚧 building |

The **Handbook** is the new big effort: not just pavois's docs, but the whole hardening
subject, **citing** (never copying) the user's blog guides under
`https://blog.stephane-robert.info/docs/securiser/…`.

## 2. Handbook page plan

Each page = original bilingual content (threat → why harden → defense principle → what
pavois audits + linked rules → "go deeper" citation to the blog).

### A. Foundations
| Page | Cite (blog) |
|---|---|
| understanding-threats | /docs/securiser/socle/menaces/runtime/ |
| why-harden | /docs/securiser/durcissement/ |
| defense-principles | /docs/securiser/socle/methode/ |
| the-standards | /docs/securiser/durcissement/cis-benchmarks/ · anssi-bp-28/ · socle/conformites/ |

### B. Domains (one per pavois domain)
| Page | pavois domain | Cite (blog) |
|---|---|---|
| ssh | SSH | /docs/securiser/durcissement/ssh/ |
| pam | Accounts (PAM) | /docs/securiser/durcissement/pam/ |
| mac | (SELinux/AppArmor) | /docs/securiser/durcissement/selinux/ · apparmor/ |
| firewall | Firewall | /docs/securiser/reseaux/firewalld/ · ufw/ · firewalls/ |
| permissions-ownership | File permissions/ownership | /docs/securiser/durcissement/acl/ |
| packages | Packages | /docs/securiser/supply-chain/securiser-dependances/ |
| journald-logging | Logging (journald) | /docs/securiser/socle/referentiel/cloud/journalisation-audit/ |
| sysctl | Kernel & network (sysctl) | ⚠️ **blog gap** |
| auditd | Audit (auditd) | ⚠️ **blog gap** |
| sudo | Sudo | ⚠️ **blog gap** |
| grub-boot | Bootloader (grub) | ⚠️ **blog gap** |
| kernel-modules | Kernel modules | ⚠️ **blog gap** |
| mounts-filesystem | Mounts / Filesystem | ⚠️ **blog gap** |
| systemd-services | systemd services | ⚠️ **blog gap** |
| time-sync | Time synchronization | ⚠️ **blog gap** |
| banners | Banners | ⚠️ **blog gap** |
| cron-at | Cron/at access control | ⚠️ **blog gap** |
| dconf | GNOME desktop (dconf) | ⚠️ **blog gap** |

### C. Tooling (the scanners)
| Page | Cite (blog) |
|---|---|
| pavois | /docs/securiser/outils/cinc-auditor/ |
| openscap | /docs/securiser/durcissement/openscap/ |
| lynis | /docs/securiser/durcissement/lynis/ |
| cis-cat | ⚠️ **blog gap** |

## 3. Blog content gaps (opportunities for blog.stephane-robert.info)

pavois covers these hardening topics, but the blog has **no focused `/docs/securiser/`
guide** yet — content the user could add:

- **sysctl / kernel-network hardening** (only the general durcissement index exists)
- **auditd** (no dedicated guide — heavily referenced by CIS/ANSSI)
- **sudo / sudoers** hardening & logging
- **GRUB / bootloader** password & cmdline
- **kernel modules** (blacklist / disable filesystems & protocols)
- **mounts & filesystem** options (nodev/nosuid/noexec, /tmp, /var)
- **systemd service hardening** (ProtectSystem, NoNewPrivileges…)
- **time synchronization** (chrony/ntp)
- **login banners / MOTD**
- **cron/at access control**
- **CIS-CAT** (the official CIS scanner)

## 4. Roadmap (phases)

- **Phase 0 — container** (now): `handbook` collection + layout (sidebar grouped by section)
  + nav. One gold page (SSH) to set the bar. → validate model + citation/SEO.
- **Phase 1 — Foundations** (4 pages): threats, why-harden, defense-principles, standards.
- **Phase 2 — Domains** (18 pages): authored by a multi-agent workflow, citing the blog where
  a guide exists; original content for the blog-gap topics.
- **Phase 3 — Tooling** (4 pages): pavois, openscap, lynis, cis-cat.
- **Phase 4 — cross-linking**: each rule page links its handbook topic; handbook pages link
  their pavois rules + the blog citation.

See also `trous-docs.md` (pavois's own doc/coverage gaps).
