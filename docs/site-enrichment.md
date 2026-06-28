# Site enrichment backlog

Captured from a 5-section content-quality audit (home/docs, handbook, standards, rules, glossary)
sampled 2026-06-26. The site already builds 1643 pages with genuinely good prose. This backlog is
about turning *well-written* into *incontournable*.

## Verdict (converged across all 5 sections)

The content is **well-written but isolated and unsourced**: it asserts without citing, and it does
not link pavois's own data together. Three layers make it a reference instead of a blog:

- **A — Credibility:** source every claim with an authoritative external reference.
- **B — Cross-linking:** wire controls ↔ glossary ↔ norms ↔ handbook into one graph.
- **C — Surface the unique data:** the effective-config check, the multi-norm crosswalk, the
  numbers (786 controls · 2823 norm refs · 235 cross ≥3 norms), per-OS variance, per-norm levels,
  OSCAL. This data exists and is mostly hidden.

---

## A. Credibility layer — external references (P1, in progress)

Add a **"Sources & references"** block to fiches, glossary terms, norm pages and handbook guides.
Verified authoritative URL patterns (checked live, non-404):

- **NIST SP 800-53 control → csf.tools** — `https://csf.tools/reference/nist-sp-800-53/r5/<fam>/<fam>-<n>/`
  (e.g. `AC-3` → `/ac/ac-3/`). Strip enhancement parens for the URL. ✅ verified.
- **man pages → manpages.debian.org** — `https://manpages.debian.org/<page>` (e.g. `sshd_config`,
  `sysctl.conf`, `auditctl`, `sudoers`). Derive the page from the check command/domain. ✅ verified.
- **Norm landing pages** — from `site/src/data/standards.json` (`cis`, `bp28`, `nist`, `pci-dss`,
  `stig` URLs + version). Always valid; show the per-OS CIS benchmark version too.
- **CVE → nvd.nist.gov** — `https://nvd.nist.gov/vuln/detail/<id>` (e.g. CVE-2024-3094 in the SSH guide).
- **STIG:** per-ID stigviewer is unreliable (404s) → link the DISA landing (`public.cyber.mil/stigs/`)
  and show the STIG id as text, not a link.

### The author's hardening guides (external source + SEO backlinks)

Per the SEO rule (original content, cite the `/docs/securiser/` guides, never `/post`), each domain
links to the matching guide on `blog.stephane-robert.info`. **New guides the author just published**
fill the domains that previously had none (sysctl, mounts, systemd, grub, kernel-modules, sudoers,
MAC). Domain → guide map (all under `https://blog.stephane-robert.info/docs/securiser/`):

| pavois domain | guide |
|---|---|
| SSH | `durcissement/ssh/` |
| Audit (auditd) / (auditd daemon) | `durcissement/auditd/` |
| Accounts (PAM modules) | `durcissement/pam/` |
| File permissions / File ownership | `durcissement/acl/` |
| Sudo | `durcissement/sudoers/` *(new)* |
| Kernel & network (sysctl) | `durcissement/sysctl/` *(new)* |
| Mounts | `durcissement/mounts/` *(new)* |
| systemd services | `durcissement/systemd/` *(new)* |
| Bootloader (grub) / Kernel command line | `durcissement/grub/` *(new)* |
| Kernel modules | `durcissement/kernel-modules/` *(new)* |
| MAC (SELinux / AppArmor) | `durcissement/controle-acces-obligatoire/`, `selinux/`, `apparmor/` |
| Firewall | `reseaux/firewalld/`, `reseaux/ufw/` |
| Logging (journald) | `socle/referentiel/cloud/journalisation-audit/` |
| Time synchronization | `services/reseau/chrony/` |
| Packages | `supply-chain/securiser-dependances/` |
| (norm) CIS | `durcissement/cis-benchmarks/` |
| (norm) ANSSI BP-028 | `durcissement/anssi-bp-28/` |

**Blog-guide gaps** (domains with no guide yet, candidates for the author): Kernel build (Kconfig/KSPP),
GNOME desktop (dconf), Passwords (pwquality), Banners, Cron/at, the Accounts sub-domains (login.defs,
umask, faillock, home dirs, password history, root PATH), Filesystem (scan).

Build: a generated `site/src/data/domain-refs.json` (domain → {handbook id, blog url+label, man pages,
official deep links}); the fiche/standard/glossary templates render a Sources block from it + the
per-control NIST/CVE links computed from the data. No content regeneration needed (computed in-template).

---

## B. Cross-linking layer (the data is a graph, render it as one)

- **Glossary → controls:** each norm term (CIS Benchmark, ANSSI BP-028, NIST AC-3…) and each technical
  term (drop-in, PAM, sysctl, auditd) links to the pavois controls that implement/verify it. *Today: zero.*
- **Glossary additions:** an "Effective configuration" mini-category — `sshd -T`, `sysctl -a`,
  `auditctl -l`, `systemctl show` as entries explaining what each resolves and why pavois uses it.
- **Fiche → handbook + glossary:** each fiche links to its domain's handbook guide (internal) and to
  the glossary terms in its prose. *Today: fiche has only the crosswalk + norms.*
- **Handbook → fiches:** each guide lists the concrete control ids it covers ("this SSH guide audits
  `ssh-permitrootlogin`, `ssh-disable-compression`…") with links. *Today: guides name no ids.*
- **Standards → cross-coverage:** on a norm page, each control shows "also satisfies +N norms"; a
  header line "PCI auditors: 145 of these controls also cover CIS + NIST". *Today: flat list.*
- **Bidirectional `related` in glossary** (Include Directive ↔ Drop-in already, extend to norms/tools).

---

## C. Surface the unique data

- **Home — "By the numbers" band:** 786 controls · 2823 norm refs · 235 cross ≥3 norms · 8 OS ·
  OSCAL baseline v0.1.0. Today the home shows none of it.
- **Home rules table — a "norms" intensity column** (how many standards each control proves).
- **Docs — a worked crosswalk example** instead of the dry "a standard is a view" sentence; an
  **OSCAL export** section (what `pavois oscal` emits + who consumes it).
- **Fiche — per-OS variance:** show that the CIS number / check differs per OS (the data is in
  `os_versions` + keyed `@os`), e.g. a small per-OS table. The single most distinctive un-shown datum.
- **Fiche — per-norm levels:** "required at CIS L1 / ANSSI enhanced" badges (data in `levels`).
- **Fiche — conformant-vs-fail sample output** for the check (helps operators read a real result).
- **Standards — coverage numbers** vs the official benchmark, per domain; link the per-OS OSCAL profile.
- **A landscape / matrix page** (was "option C"): domains × norms matrix, the multi-norm share, the
  versioned baseline + OSCAL download. The bird's-eye entry point.

---

## Per-section notes (from the audit)

- **Home / Docs:** prose repeats "effective config" 3× without proof; no numbers, no OSCAL, no
  crosswalk example. FR is a literal echo of EN in places.
- **Handbook (26 guides):** prose is *excellent* (CVE-2024-3094 named, threat→defense structure) but
  abstract — no real `sshd -T` output, no "silent drop-in" demo, no per-OS notes, no control ids.
- **Standards (5):** the "how to read references" notation is a standout; the control table is thin
  (no titles for the section numbers, no cross-coverage, no coverage %, no OSCAL link, no baseline ver).
- **Rules (786):** ~74% rich / ~26% thin. 192 fiches (24%) have empty remediation (legit for Kernel
  build; fixable for Accounts/Firewall). ~10 fiches are skeletons (e.g. `firewall-default-deny`: no
  rationale/verify/impact). Per-OS variance & levels are in the data but unshown.
- **Glossary (191):** definitions are substantial and fully bilingual (no FR=EN clones) — but isolated
  (zero links to controls/norms), only 5 pavois-specific terms, "fondamentaux" is a catch-all.

## Sequencing

P1 **A (references)** — universal credibility, SEO backlinks, uses the just-published guides.
P2 **B (cross-linking)** — turns 4 isolated content types into one graph (biggest "stickiness" gain).
P3 **C (surface data)** — the home numbers band + the landscape page + per-OS variance on fiches.

## CSS architecture (noted 2026-06-26)

- [ ] **Non-inline CSS.** The maquettes inline the full pavois.css in a `<style>` block; the site
  must use the shared external `site/src/styles/pavois.css` (done) and avoid per-page `<style>`
  blocks. When porting a page, push any reusable rule into pavois.css rather than a scoped page
  `<style>` (e.g. `.fsearch`, table sort-arrows, `.empty` added during the /rules port should move
  to pavois.css). Goal: one shared design-system stylesheet, no duplicated/inline page CSS; prune
  global.css once all pages are ported off it.
