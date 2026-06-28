# Site review — ChatGPT challenge #3 (verification pass)

Model **5 → 6.5**. The round-2 fixes are confirmed REAL, not veneer (evidence types exist,
scoring page exists, coverage admits limits, tools page less caricatural). Verdict of the 5
round-2 attacks: all **PARTIAL** — none fully closed, one regressed (a contradiction we introduced).

Next weak point is no longer "can Pavois read more than files?" but **"what exactly does a PASS
prove?"** — the evidence is typed, the verdict is still flat. Reviewer's single highest-value
chantier: turn evidence_type into a full **verdict model** (below).

## P1 — contradictions / overclaims we introduced or left (site-side, fix now)

- [x] **Crosswalk banner contradicts the evidence type** — fiche `faillock-deny` is tagged
      `persistent-config`, yet the crosswalk banner still says "One **effective-config** check"
      and "Pavois asserts the **effective** configuration — live, resolved state, not a file".
      `cx.oneCheck` + `cx.effective` are hardcoded to the runtime story for EVERY control.
      → neutralise "One check"; render the effective/resolved note ONLY for `effective-runtime`
      (the per-type `.ev-note` already covers the others).
- [x] **evidence-and-exports page generalises "effective-config check"** — says every scan records
      "the effective-config check it ran" (+ sshd -T) while the base has persistent/inventory/
      filesystem controls. → "evidence check" + document the 6 types (what each proves / doesn't).
- [x] **/standards/nist still says "satisfies both standards"** — too strong for abstract NIST
      families. → "supports / provides evidence toward"; a `supporting` marker per NIST ref.
      (the B4 reword missed the standards/[norm] page.)

## P1 — the deep one (engine): scoring ignores persistence

- [x] **Score is flat across evidence types** — SHIPPED (policy: cap + qualifier). A PASS on
      runtime-only evidence (`effective-runtime`/`behavioral`) no longer counts as a full pass:
      `audit.FullPass`/`audit.Proves` derive the verdict from the evidence type, `Evaluate`
      counts `Qualified` runtime-only passes, and `GradeResult` caps an otherwise-A grade to **B**
      and flags it **runtime-qualified**. Points (failure-driven) are unchanged — only the letter
      caps. Surfaced in the CLI scorecard/headline, the HTML report (client `grade()` mirrors Go,
      `validate_grade.py` keeps weights in sync), `scan --format json` (`runtime_qualified` +
      `qualified_passes`), `diff`, and OSCAL (`proves-*` props, single source `audit.Proves`).
      PERSISTENCE PHASE 1 SHIPPED → second axis `reboot_survivable` (yes/no/unknown), derived by
      `tools/gen_reboot_survivable.py` (mise gen:reboot), flows DRY to the corpus (`tag reboot:`)
      and the engine (`audit.fullPassFor`). The cap now fires ONLY on genuinely-live passes
      (debian12: 101 → 29 runtime-only) — config-derived/compile-time reads (sshd -T, kconfig)
      correctly count as full. Companion-aware logic is wired (`requires_companion_control` /
      `tag companion:`): a live control becomes a full pass iff its persistent companion passes.
      PHASE 2 (hybrid) → fold persistence into the template checks where clean, separate
      companions for the rest. DONE (all 3 template categories, validated on debian12 via the
      product path): 2a sysctl (live value AND a pinned /etc/sysctl.d entry; unpinned now FAIL;
      runtime-qualified 29→9), 2b kmod (already reboot-proof via be_disabled/modprobe.d →
      reclassified), 2c mount (live option AND fstab/systemd .mount; partition-dev-shm validated
      reboot-proof; 9→7). Live set 200 → ~82. The engine companion path (fullPassFor + companion)
      is built and unit-tested (TestFullPassFor) but not yet exercised with real corpus data.
      2d DONE: cmdline (18 → `cmdline` template, /proc/cmdline + grub) and auditd (22 → `audit_rule`
      template, auditctl -l + /etc/audit/rules.d) templatized and folded. Persistence phase 2
      COMPLETE for every foldable category — live set 200 → 42. The remaining 42 are LEGITIMATELY
      runtime-only (auditctl -s, MAC getenforce/aa-status, service is-active, live firewall): no
      clean persistence source to fold, so they stay runtime-qualified, honestly. A host now earns
      a clean A only by proving active AND reboot-survivable — the "reboot-proof mode" differentiator.

## P2

- [x] **Mapping still not per-mapping auditable data** — the-standards explains direct/supporting
      in prose, but the fiche shows only standard refs, not a per-mapping table
      (type / version / source / reviewer / date / confidence). Heavy B4.
- [x] **Coverage not wired to score/rules** — per-domain coverage depth now surfaced from a single
      source (`site/src/data/coverage.ts`, mirrored from /handbook/coverage): a `shallow` badge on
      the affected rows of the /rules explorer (linking to the Coverage page), the thin-domain
      caveat on those fiches (DRY'd onto the same source), the depth matrix on /handbook/coverage,
      and the reboot-proof coverage chip on /standards. (Only the Go HTML scan report is not yet
      annotated — minor follow-up.)
- [x] **/docs/tools still tool-vs-tool** — pivot to a by-evidence-type comparison
      (runtime / persistence / inventory / filesystem / remediation / reporting / official-standard).

## P3

- [x] **Glossary "No term matches." artifact** — flagged twice; appears in scraped/no-JS view
      (the hidden empty-state `<p>` is read as content). Also generic terms (Abstraction, API Key,
      CORS) dilute Linux-hardening relevance. → only render empty-state when actually empty (JS or
      conditional), prune/scope the term list.

## The headline chantier — verdict model (reboot-proof)

Per control, make evidence COMPUTABLE / VISIBLE / SCORED / EXPORTED:

```yaml
evidence_type: effective-runtime | persistent-config | inventory-state | filesystem-state | manual | behavioral
proves:
  runtime_state: true|false
  persistent_state: true|false
  reboot_survivable: true|false|unknown
  behavioral_enforced: true|false|unknown
limits: ["Runtime value may not survive reboot", ...]
score_policy:
  counts_as_full_pass: true|false
  requires_companion_control: <id>
```

e.g. `audit-immutable` → runtime pass / persistent unknown → `runtime_pass_persistence_unproven`
→ score partial. The differentiator nobody else formalises: say precisely what a PASS proves
**and what it does not**. Pavois then sells "qualified evidence", not "the truth".
