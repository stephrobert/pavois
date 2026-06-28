# Site review — ChatGPT challenge #4 (raised bar: functional tool / reference / onboarding / guides)

Overall **6/10**. Axes: functional tool **4**, reference **6.5**, onboarding **5**, guides **6**.
Maturity: between "advanced POC" and "emerging reference". To level up: a REAL distribution +
a complete reproducible scenario (release + repo + binary + container + example report + vulnerable
fixture + before/after harden/reboot/re-scan).

## Top blockers (from the audit)

1. **Install not usable** — Get started still has `git clone <pavois-repo>`; no real repo URL.
2. **reboot-proof / scoring contradiction** — home & qualified-verdict said the cap is shipped;
   scoring-methodology said "still counts as a full pass / planned". FIXED (scoring page aligned).
3. **"single Go binary" unproven** — no release / checksum / signature / container / deb-rpm.
4. **OSCAL partial** — catalog + profiles shipped; assessment-results still roadmap.
5. **Coverage thin** on firewall / logging / time-sync / MAC (honestly disclosed, but real).

## Triage

### DONE this pass
- [x] **#2 contradiction** — scoring-methodology rewritten (EN+FR) to state the implemented cap
      (runtime-only PASS caps to B / runtime-qualified; `harden apply --reboot --scan` = reboot-proven).
      Home / qualified-verdict / blog already matched; all four are now consistent. Unit test
      `TestGradeResult` already proves the cap.
- [x] **P3 FR residual English** — localized the two `reads` strings in the FR home thesis cards.

### DOABLE without input (content/site, no fabrication) — proposed next
- [ ] **Promised / delivered / roadmap matrix** (a /docs or home section): effective config,
      harden-as-code, reboot-proof, OSCAL catalog vs assessment-results, CI, SARIF/JUnit, verify.
- [ ] **Example HTML report** linked publicly (a real before/after scan output placed under
      site/public/) — proves the tool, not just claims.
- [ ] **CI how-to** (GitHub Actions): real YAML, `--fail-under`, exit codes 0/100/101, SARIF upload,
      HTML/JSON artifacts. All confirmed facts.
- [ ] **Installation page** separate from Get started: build-from-source + CINC native/omnitruck +
      Docker fallback + sudo/SSH prereqs + supported OS + common errors. (Repo URL still a
      placeholder until provided.)
- [ ] **Coverage levels in /rules**: extend the shallow badge to a per-domain deep/partial/shallow
      indicator (partial needs a curated 3rd bucket).
- [ ] **/docs/tools "promised vs delivered" honesty** already good; keep.
- [ ] P3: prune generic glossary terms; more blog posts; per-page author/version on method pages.

### BLOCKED on a decision (you)
- [ ] **#1 real repo URL** — needed for Get started + Installation. (No git remote configured.)
- [ ] **#3 signed release pipeline** — binary (amd64/arm64) + SHA-256 + provenance + changelog,
      and/or container image, `.deb`/`.rpm`. Needs the distribution strategy + a release host.
- [ ] **Tool features** (bigger, CLI work): `pavois demo`/fixture, `pavois doctor`, `scan local
      --quick`, `report open`, `--dry-run --explain` for harden, OSCAL assessment-results export.
      These are real engine tasks, scheduled once distribution is decided.

## Already solid (do not regress)
Control fiches (SOCLE id, evidence type, "a pass proves", direct/supporting mappings + version/
confidence, InSpec check, manual verify, remediation, impact, sources); the honest tool comparison
(OpenSCAP/SSG maturity acknowledged); the coverage / non-coverage page.
