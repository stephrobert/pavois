# Site review — ChatGPT challenge #2 (model + content)

Second adversarial pass. Verdict: **not yet THE reference**. The content is past
"just another blog"; the blocker is now **opposable methodology**, not copy. The
model (effective-config, 1-control-N-norms, A→E grade, OSCAL, SOCLE) is promised
harder than it is proven — governance, method proof, and limits are under-exposed.

Scores: Depth 6.5 · Credibility 6 · Originality 8 · Coverage 6 · **Model 5** ·
Honesty 6.5 · UX/SEO 7.

Source tunnel of the review: medicare-manufacturer-royal-bloom.trycloudflare.com

---

## A. Quick wins (copy / UX — low risk, do first)

- [ ] **#9 Glossary empty-state bug** — "No term matches." shows while terms are
      listed (contradictory). Fix the filter/empty-state logic. Then prioritise
      product terms (effective configuration, runtime vs persistent state,
      drop-in, Include, OSCAL catalog/profile/assessment-results, InSpec
      resource, not-applicable, manual evidence, control mapping, compensating
      control) and link each to a fiche / handbook page.
- [ ] **#10 FR i18n leak** — `/fr/` home still has English fragments in the demo
      (`reads /etc/ssh/sshd_config`, `reads sshd -T`). Add an i18n guard: no
      residual EN in `/fr/` (outside commands), no FR in `/en/`.
- [ ] **#1 Soften the absolute thesis** — home "only the effective read tells
      the truth" + `/rules/` "every control is audited against the resolved
      configuration" is false for file-ownership/permissions/packages/dconf/
      bootloader. Reword to an evidence-type aware claim (see B-typology).
- [ ] **#5 Tool comparison too aggressive** — `/docs/tools/` "blind / cannot do"
      overclaims. OpenSCAP/SSG = full SCAP datastreams + remediation; CIS-CAT =
      official CIS tool; Lynis = audit+hardening. Replace "blind spot" with an
      honest use-case matrix (stronger-on-effective, not "others see nothing").

## B. Methodology (the real work — makes the model opposable)

- [ ] **Evidence-type typology** (underpins #1/#2). Tag every control with its
      evidence kind: `effective-runtime` (sshd -T, auditctl -l, systemctl show) ·
      `persistent-config` (drop-ins, kernel cmdline) · `inventory-state`
      (packages/services present) · `filesystem-state` (perms/owners/SUID) ·
      `manual-evidence` · `behavioral-test`. Surface it on each fiche + in OSCAL.
      → schema field in rules.yml, render to corpus + fiches + report.
- [ ] **#2 Runtime ≠ persistence** — for runtime-checkable controls, emit a dual
      verdict: `runtime_state` + `persistent_state` + `reboot_survivable`.
      Scoring must NOT mark a control fully compliant when runtime passes but
      persistence is absent (`runtime_only` / `temporarily_compliant`).
- [ ] **#4 Scoring methodology page** `/handbook/scoring-methodology/` — publish
      the formula: weighted passed / applicable weighted; **critical-failure
      grade caps** (any critical fail → max C; remote root login → max C; audit
      disabled → max C; no firewall on exposed role → cap); manual / N-A
      handling; per-standard weights; per-level filters. Reproducible worked
      examples. (Today A→E reads arbitrary.)
- [ ] **#3 Mapping governance** — a mapping is an interpretation, not an
      equivalence. Add per-mapping metadata: `mapping_type`
      (direct/partial/supporting/inferred/manual-review/disputed/withdrawn),
      source, **standard version**, rationale, reviewer, date, confidence.
      Ban "proves compliance with N standards" when a mapping is only
      `supporting`. Add mapping non-regression tests.
- [ ] **#6 SOCLE governance page** — kill the "author wrote the norm his tool
      conforms to" circularity. Position SOCLE as a **neutral namespace +
      crosswalk model, NOT a certification authority**. Page: status
      (non-certifying), version, maintainers, contribution/RFC process, change +
      deprecation rules, external-referential mapping, proof Pavois doesn't
      "pass" because SOCLE was written for it.
- [ ] **#7 OSCAL download bundle** `/downloads/` — catalog + per-OS profiles +
      sha256 + signature + changelog + schema validation + an
      **assessment-results** example from a real scan + a GRC import example
      (ciso-assistant). Remove the leftover OSCAL-download TODO in Evidence.
- [ ] **Coverage / non-coverage matrix** — show what Pavois does NOT cover
      (containers runtime, immutable hosts, cloud images, secrets rotation,
      SELinux custom policy, custom kernels). Counter-intuitive but builds trust.

## C. Depth / differentiators (content that demonstrates, not claims)

- [ ] **#8 Handbook domain skeleton** — enforce per domain: threat model ·
      common mistakes · controls covered · controls NOT covered · verification
      commands · Debian/RHEL examples · operational impact · legitimate
      exceptions · primary references · links to fiches. (MAC page e.g. is too
      thin: just defers to two blog posts.)
- [ ] **Reproducible per-rule labs** — compliant fixture + non-compliant fixture
      + expected Pavois result + expected OpenSCAP/Lynis behaviour + why the
      difference matters. The SSH strict-config-with-permissive-drop-in lab is
      the flagship: *demonstrate* the edge, don't assert it.
- [ ] **"Reboot-proof mode"** (the headline differentiator nobody sells):
      `pavois prove <target> --reboot-window controlled` → runtime pass /
      persistent pass / post-reboot pass. Engine work; ties to B-runtime≠persist.

---

### Triage note
A = ship now (UX/honesty). B = the spine of "reference-grade" (schema + Go
engine + new pages) — sequence after A, biggest payoff is the evidence-type
typology since #1/#2/#4 all lean on it. C = ongoing depth once the model is
formalised. The reviewer's one-line: next chantier is **opposable methodology,
not marketing**.
