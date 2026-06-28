# Site review — ChatGPT (2026-06-26)

External content/credibility review of the live site (via trycloudflare tunnel). Verdict: **strong
base, not yet an "incontournable reference."** The differentiator (audit the *effective* state +
one control → N norms) lands; the blocker is **proof of method** — governance, nomenclature, limits,
exports, evidence, and coverage honesty must be made visible. This is the working backlog; items are
grouped by the reviewer's priority. Tick as done.

## P1 — fix before any strong publication

- [x] **Home — false breadth claim.** "Every rule is cross-validated against at least two independent
  authorities" is contradicted by single-norm rules (e.g. `SOCLE-CLD-IAM-025` shows "1 standard",
  CIS only). Reword to "Most rules map to multiple standards; single-standard rules are explicitly
  flagged." Add visible counters: `multi-standard`, `single-standard`, `source-only`, `manual review
  needed`. (Source string is in `site/src/i18n/ui.ts`.)
- [ ] **Home/Docs — OSCAL not exploitable.** "v0.1.0 OSCAL baseline" is announced but there is no
  download / changelog / hash / schema / validation in the visible path. Add a **"Download the
  baseline"** block: OSCAL JSON, CSV, bundle JSON, checksum, release notes, coverage matrix,
  generated-at, source commit. Critical for the GRC audience. (We already emit `oscal/` — wire it up.)
- [x] **SOCLE nomenclature page.** The ref `SOCLE-CLD-SSH-020` is shown but never explained in the
  journey. Create a **"SOCLE control ID model"** page: `SOCLE-<domain>-<family>-<number>`, examples,
  ID stability, versioning, deprecation rules, link to SOCLE. Add a tooltip on each ID.
- [x] **"Produce audit evidence" guide (Docs/GRC).** Docs cover scan/harden but not the evidence
  package: how to produce auditor-usable proof — command, HTML/PDF/JSON/SARIF/CSV output, hash, OS
  context, profile version, normative mapping, known limits, example audit folder.
- [ ] **Per-fiche source status.** Some fiches are "normative" but show no official-standards block,
  only a man page (e.g. `logindefs-fail_delay` / FAIL_DELAY), while the home promises broad normative
  validation. Add a status per fiche: `normative mapping` / `technical source` / `manual mapping
  pending`. Never leave a normative rule without a visible normative source.

## P2 — convince in under 30 seconds

- [x] **Home — demonstrate "1 check = N standards"** with a mini visual under the hero:
  `LoginGraceTime = 60` → CIS + PCI-DSS, then `faillock deny ≤ 3` → ANSSI + CIS + NIST + PCI + STIG.
- [ ] **Home — guided entry before the 786-row table:** "I'm a sysadmin", "I'm an auditor", "I'm
  evaluating pavois vs OpenSCAP/Lynis."
- [ ] **Handbook — "Start here" path:** 1) Why pavois, 2) Standards, 3) SSH, 4) auditd, 5) first scan.
- [ ] **Fiches — standardise the rich level** across all fiches (rationale, effective check, manual
  verification, logs, remediation, impact, sources). The good ones (SSH LoginGraceTime, faillock,
  auditd) are the bar.
- [x] **Glossary — empty-state BUG:** shows "No rule matches" while entries are listed. Fix the
  empty-state. Add links from key terms to rules ("Effective configuration" → SSH/sysctl/auditd
  rules; "Drop-in" → concerned rules).

## P3 — SEO / trust / readability

- [ ] **Norm pages — summary header** before the table: coverage by domain, OS, severity, multi-norm
  rate. Today the table arrives too fast for a busy auditor.
- [x] **Handbook OpenSCAP — soften the tone.** "blind to Includes/drop-ins" reads as a pamphlet;
  prefer "file-oriented checks can miss layered runtime configuration depending on rule implementation."
- [x] **Move the GRC argument up.** The "one neutral rule, N views" + per-OS version-pinning passage
  is one of the best GRC arguments but is buried in the handbook → surface on the home.
- [ ] **Glossary — prioritise product terms** (effective configuration, drop-in, CINC/InSpec,
  SCAP/OVAL, baseline, control, evidence, remediation); keep generic terms (DORA, RASP, Zero Trust)
  but less prominent.
- [ ] **Dedicated "Attribution & licensing" page** (origin ComplianceAsCode/SSG, non-affiliation
  CIS/PCI/STIG/NIST, NIST/STIG public domain). Transparency = a trust argument for a compliance tool.

## Persona gaps

- **Sysadmin:** 5-minute quickstart (Debian/Ubuntu/RHEL); sudo / no-sudo matrix; lab mode with a
  deliberately non-compliant VM; before/after report examples; rollback/recovery for risky rules.
- **Auditor / GRC:** downloadable versioned OSCAL export; coverage matrix (norm/OS/domain); mapping
  traceability proof; single-norm control status; example evidence folder ready to attach to an audit.

## Top 5 to become incontournable (reviewer's synthesis)

1. **"Evidence & exports" page** — OSCAL, JSON, CSV, hash, changelog, profile version, source commit.
2. **"SOCLE nomenclature" page** — explain the ID model, stability, versioning.
3. **GRC coverage matrix** — by norm, OS, domain, severity, CIS/ANSSI/STIG level.
4. **Fix over-broad claims** — drop "every rule ≥2 authorities" while single-norm rules exist.
5. **Persona paths** — sysadmin, auditor, RSSI/GRC, security maintainer.

## Governance gap (the deepest credibility blocker)

The référentiel's governance is invisible: **who validates the mappings, how CIS/ANSSI/NIST
disagreements are resolved, how a rule changes version, how a rule is deprecated.** Make this a page —
it's what separates a "good technical site" from "the Linux compliance reference."

## Quick wins spotted (cheap, high signal)

- The home over-broad claim (one string in ui.ts) — factually wrong, fix first.
- The glossary empty-state bug ("No rule matches").
- Wire the existing `oscal/` artifacts into a download block (data already produced).

---

# Home redesign (second ChatGPT pass, 2026-06-26)

Diagnosis: **the home reads as a référentiel index, not a product landing.** It jumps from the
slogan almost straight to a 786-row filtered table. Good for someone who already knows the topic,
too brutal for a first-time visitor — a decision-maker/RSSI/auditor may conclude "just another big
Linux hardening rule base." The real message ("an executable, sourced, versioned, evidence-oriented
Linux baseline that audits the *applied* state") isn't frontal enough.

## Architecture — split landing from explorer (P1)

- [x] **`/en/` = a real product landing** (promise → problem → differentiation → demo → personas →
  numbers → CTA).
- [x] **`/en/rules/` = the controls explorer** (filters, full 786-row table, domains, norms, search).
  Move today's home table here; it's an excellent exploration page, not the first product screen.

## Recommended home structure (top → bottom)

1. [ ] **Hero — a product promise in 10s, not a technical explanation.** Reword the current "audits
   the EFFECTIVE configuration… not files" into: *"The Linux compliance scanner that audits what is
   actually applied, not what is supposed to be configured."* Subtitle: effective state via
   `sshd -T` / `sysctl` / `auditctl` / `systemctl show`, **and** each control maps to CIS / ANSSI-BP-028
   / NIST / PCI-DSS / STIG. CTAs: `Get started` · `Browse controls` · `View standards coverage`.
2. [ ] **Short demo** — `pavois scan local --profile socle-linux` + a synthetic result block
   (Host, Controls 786, Failed 42, Mapped standards, Evidence mode: effective configuration).
3. [ ] **Why pavois is different — 3 cards:** *Effective configuration* (`sshd -T`, `auditctl -l`,
   `sysctl -a`), *One check, many standards*, *Evidence-ready* (each fiche: verification, remediation,
   impact, sources).
4. [ ] **Example control inline** — a simplified fiche on the home (e.g. `SOCLE-CLD-SSH-020`
   LoginGraceTime: effective check, mapped-to, remediation). More convincing than a 786-row table.
5. [ ] **Norm coverage — keep the numbers but place them AFTER the value demo** (786 controls ·
   2,823 norm refs · 235 cross ≥3 · 8 targets · OSCAL v0.1.0), not before the product is understood.
6. [ ] **Guided paths — "What do you want to do?"** table: Scan a Linux host → Quickstart · Harden SSH
   → SSH controls · Produce audit evidence → Evidence guide · Map to ANSSI-BP-028 → ANSSI coverage ·
   Compare with OpenSCAP/Lynis → Why effective config.
7. [ ] **Rules table — keep, but lower** (or solely on `/en/rules/`).

## Persona doors (three visible entry points)

- [ ] **Sysadmin — "I want to harden a Linux server":** scan local → see gaps → remediate → verify
  effective state.
- [ ] **Auditor / GRC — "I want to prove compliance":** CIS/ANSSI/NIST/PCI/STIG matrix → export
  results → consult evidence → download the OSCAL baseline.
- [ ] **RSSI / platform owner — "I want to standardise Linux hardening":** pick a baseline → track
  drift → version requirements → integrate into CI/CD or fleet management.

Today the nav (Docs, Handbook, Rules, Standards, Glossary) never says **who each is for** — make it explicit.
