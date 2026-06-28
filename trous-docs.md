# Documentation gaps — pavois

Status of the doc/coverage gaps. Many items are now **closed** by the CLI docs and the handbook.

## ✅ Closed

- **User CLI docs** — every command, option, workflow and example → `/docs/`.
- **harden plan → apply** documented (edit the plan: flip `apply: false` → `true`); the rule-page
  command was wrong (`apply local`) and is fixed to `pavois harden plan local`.
- **Concept docs** — threats, defense principles, the standards → the **handbook** (26 pages).
- **Blog cross-linking** — the handbook **cites** the blog `/docs/securiser/` guides (no copied
  text; SEO-safe backlinks).
- **NIST two-publications now deliberate + explained.** Every control carries BOTH the 800-53
  (`AC-3`) and 800-171 (`3.1.7`) form (cross-OS union of pavois's own tags; 800-53 base coverage
  0 → 38-43 per OS). Each standards page now has a **"how to read the references"** notation guide.

## 🕳️ Open — pavois content / coverage

- **P2 — STIG is Ubuntu-only.** STIG IDs only via the two Ubuntu OSes (UBTU); none for
  RHEL / Debian / Alma. Per-rule STIG lists are long (e.g. 44 on one auditd rule) → a display
  policy (truncate + expand).
- **P2 — ANSSI BP-028 coverage.** 41 of 80 R-numbers mapped (the rest are largely
  organisational/physical, out of a host scanner's scope). Tags are now **validated against the
  OFFICIAL v2.0 PDF** (`mise run validate:bp28`) — all valid, no v1.2 residue. R10 (disable kernel
  module loading) was a real gap, now closed (`kmod-loading-disabled`).
- **P2 — debian13.** SSG immature (25 sections); ~37 CIS mappings in neither SSG nor
  ansible-lockdown → review/clean.
- **P3 — fedora.** No CIS benchmark exists — explain on the site so the empty CIS column isn't
  read as a bug.

## 🕳️ Open — pipeline / integration

- **P2 — Enriched content in the API.** `pavois rules` should serve the enriched per-id bilingual
  content (relocate the store to a neutral `content/rules/` read by both the Go API and the site).
- **P2 — Reverse cross-link.** Each rule page → its handbook topic (handbook → rules already done).
- **P3 — Norm-watcher.** The studio's `check_updates` exists but isn't scheduled.

## 🚧 Blog content gaps — being filled by the user

pavois covers these topics but the blog had no focused `/docs/securiser/` guide; the user is
creating them now. Each already has an **original pavois handbook page** — when a blog guide goes
live, add its URL to that page's `cite` array (handbook `<id>.json`):

`sysctl` · `mounts-filesystem` · `grub-boot` · `kernel-modules` ·
`systemd-services` · `banners` · `cron-at` · `cis-cat`

**Live (cite added):** `auditd` → /docs/securiser/durcissement/auditd/.

See `docs-roadmap.md` for the full content IA + handbook plan.
