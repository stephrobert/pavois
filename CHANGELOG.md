# Changelog

Two things in this project carry a version, and they move independently. This file tracks both,
because a reader who archives a report needs to know which of the two changed.

- **The tool**, the `pavois` binary. A git tag names it. A fix to the scanner is not a change to the
  standard it evaluates.
- **The baseline** (`pavois-baseline`, identity in `docs/reference/baseline.yml`), the published
  hardening standard `pavois oscal` emits. MAJOR when controls are removed or ids renamed, MINOR
  when controls or mappings are added, PATCH for fixes that do not change coverage.

Every report cites the baseline version **and its content digest**, so an archived result stays
interpretable long after the tool has moved on. Format follows
[Keep a Changelog](https://keepachangelog.com); versioning is semantic.

---

# The tool

## [Unreleased]

## [0.1.0]: 2026-09-16

First release of the binary. Ships baseline `pavois-baseline` 0.2.0, embedded.

### Added

- `pavois scan` audits a local, SSH or Docker target through CINC Auditor and grades it A to E.
  Controls read the **effective** configuration (`sshd -T`, `sysctl`, `systemctl show`,
  `auditctl -l`) rather than configuration files, so a drop-in that re-enables what a file forbids
  is seen.
- A self-contained HTML report, chaptered by standard, with a grade, a severity breakdown and
  client-side standard and level selectors. Also JSON, SARIF, JUnit and CSV, and `--fail-under N`
  to turn the grade into a CI exit code.
- Each control declares its **evidence type** (`effective-runtime`, `persistent-config`,
  `inventory-state`, `filesystem-state`), because a pass does not prove the same thing in each case,
  and a runtime pass is not a reboot-survivable one.
- `pavois harden plan` produces a reviewable YAML plan from a real scan, and `harden apply` runs it
  through Chef. Dangerous remediations are held back by default, and the engine never installs
  itself on a target without `--bootstrap-cinc`.
- `harden apply --reboot` proves the reboot happened by comparing the kernel `boot_id` before and
  after, then re-scans, so a setting that only holds until the next boot cannot pass silently.
- `pavois verify` attempts the forbidden action and confirms the protection actually holds, rather
  than re-reading the setting that was just written. `pavois rollback` reverts an applied plan.
- `pavois bundle` packages a campaign (before and after scans, plan, reports, transition delta,
  manifest, checksums) into a tamper-evident directory, and `bundle verify` re-checks all of it.
  Signing is the operator's, under their own identity: Pavois never holds a key.
- `pavois diff` compares two scans or two plans: fixed, regressed, newly applicable, grade delta.
- `pavois rules` and `pavois norms` expose the rule base and the standard catalogue as JSON, and
  `pavois doctor` checks the environment before anything else does.
- Release artifacts are pulled from the repository's GitHub releases: static binaries for linux and
  darwin on amd64 and arm64, `.deb` and `.rpm` packages, `checksums.txt`, a CycloneDX SBOM, a SLSA
  build-provenance attestation and a keyless Cosign signature. All three proofs are checkable
  without any access to the repository.

### Validated

- Debian 12 and Debian 13, end to end, on fresh VMs created by the published tooling: stock scan,
  plan, apply, reboot, re-scan, a second pass re-planned from the resulting state, and an evidence
  bundle verified at the end. `tools/golden_path.sh` is that campaign, runnable by anyone.
- Every scan in those campaigns was itself checked by `tools/validate_run.py`, which refuses a run
  whose controls returned verdicts they never measured.

### Known limitations

- The other seven OS targets are curated and statically validated, but no end-to-end campaign has
  been run on them. Treat them as experimental and report what you find.
- Some controls ship no automated remediation (kernel rebuilds, partitioning, judgement calls).
  Pavois delivers the recipe and says so; it does not pretend to apply it.
- The grade is capped by severity class, so closing a handful of medium findings often does not move
  the letter. The posture breakdown per class is the number to read.
- OSCAL output is the baseline (catalog and profiles), not yet a per-scan assessment-results
  package. No container image is published yet.

---

# The baseline

All notable changes to the **published baseline** (the standard `pavois oscal` emits, identity in
`docs/reference/baseline.yml`). The baseline is versioned independently of the pavois tool.

## [0.2.0]: 2026-07-15

### Added
- **Two new OS targets**: RHEL 10 (`rhel10`) and Ubuntu 26.04 (`ubuntu2604`), bringing the corpus
  to **789 OS-neutral controls across 9 Linux targets**. Their CIS numbers are inherited from a
  sibling benchmark (RHEL 9 and Ubuntu 24.04 respectively) until a dedicated benchmark ships; the
  inheritance is declared in `docs/reference/norms.yml` and shown, marked as inherited, on the CIS
  standard page. This is a MINOR bump: controls and OS profiles were added, no control id was
  removed or renamed.

### Changed
- **AlmaLinux 9 is no longer a separate rendered profile**: AlmaLinux and Rocky 9 now auto-detect
  to `rhel9` (the control set is identical, and el9 kconfig uses `CONFIG_MITIGATION_*`). No neutral
  control **id** was removed, so this stays MINOR: the `almalinux9` profile was a rendering of the
  same ids, not a distinct set of controls.
- OSCAL catalog + profiles regenerated from the reference (`pavois oscal`), now 789 controls and 9
  per-OS profiles, stamped `pavois-baseline 0.2.0`.

## [0.1.0]: 2026-06-26

Initial public baseline.

### Added
- **786 OS-neutral controls** auditing the **effective running configuration** (`sshd -T`, `sysctl`,
  `auditctl -l`, `systemctl show`, `nginx -T`…): not configuration files: across 8 Linux targets:
  Debian 12/13, Ubuntu 22.04/24.04, RHEL 8/9, AlmaLinux 9, Fedora.
- **Multi-norm mappings** per control, the standard as a view never a duplicated rule: CIS (per-OS
  benchmark version), ANSSI-BP-028 v2.0, NIST SP 800-53 Rev 5 / 800-171, PCI-DSS 4.0, DISA STIG.
- **OSCAL 1.1.2 publication**: `pavois oscal` emits a catalog (grouped by domain, each control
  carrying `method=effective-config` + the real check + per-OS CIS/STIG props + norm links) and 8
  per-OS profiles, consumable by any GRC/OSCAL tool (e.g. intuitem/ciso-assistant).
- **DRY single source** (`docs/reference/rules.yml`, one control per id) + **7 check templates**
  (file_owner, package, sysctl, kconfig, service_disabled, mount_option, kmod_disabled) covering 55%
  of controls: the recurring check patterns defined once.
- Remediation recipes (Chef-engine `harden apply`/`verify`) and a deliver-don't-execute `manual`
  primitive for fixes that must not be auto-applied.
