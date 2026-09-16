# Changelog

Notable changes to Pavois. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Two things here carry a version, and a reader who archives a report needs to know which one moved:
the **tool**, which a git tag names, and the **baseline** (`pavois-baseline`, identity in
`docs/reference/baseline.yml`), the published hardening standard the scanner evaluates. A fix to the
scanner is not a change to the standard it evaluates. Every report cites the baseline version **and
its content digest**, so an archived result stays interpretable long after the tool has moved on.

## [Unreleased]

## [0.1.1] - 2026-09-16

Every artifact of 0.1.0 installed cleanly and could not scan anything. This release makes them work.
The baseline is unchanged: no control moved, so an 0.1.0 report stays comparable to an 0.1.1 one.

### Fixed

- **A released binary could not find its own rules.** The corpus was genuinely compiled in, and the
  lookup asked the filesystem: `os.Stat(<root>/profiles/linux/<os>)`. Inside a git checkout that is
  true and everything worked. Anywhere else it is always false, so no candidate was produced, the
  embedded fallback was never reached, and every packaged install answered `no bundled profile for
  debian 12.15`. `pavois profiles` printed an empty list for the same reason, which reads as "this
  tool has no rules" rather than as a bug. The lookup now consults the embedded corpus as well as
  the disk, and `pavois profiles` merges both.
- **Installing the packages no longer leaves the scan engine unsaid.** CINC Auditor is a runtime
  dependency that no package manager can fetch, because it is in no distribution repository. It
  could not be declared, so it was not mentioned at all, and the first scan failing with `no native
  CINC engine found` was reported as missing dependencies. The packages now print the omnitruck
  command and point at `pavois doctor` at install time.

### Testing

Nothing caught the profile defect because everything ran from the repository: the unit tests, the
validation campaigns, the preflight. Three guards now cover the gap, cheapest first.

- `tools/release/standalone_binary.sh` runs the built binary from an empty directory with no
  `profiles/` above it, and fails if the corpus is invisible or no scan grades. Two seconds, and it
  fails on the published 0.1.0 binary.
- The preflight extracts the binary **from the .deb it just built** and runs that same check on it,
  so the chain is closed end to end rather than at the packaging step.
- `tools/release/install_matrix.sh` installs the real packages on a fresh VM of five distributions,
  one at a time, and asserts what a first-time user meets: the manager accepts the package, the
  binary is static, the embedded corpus is listed, and a scan resolves a profile and grades.

## [0.1.0] - 2026-09-16

First release. Everything below ships in it; nothing was published before, so there is no earlier
history to read. The embedded baseline is `pavois-baseline` 0.2.0.

### The scanner

- `pavois scan` audits a local, SSH or Docker target through CINC Auditor and grades it A to E.
  Controls read the **effective** configuration (`sshd -T`, `sysctl`, `systemctl show`,
  `auditctl -l`) rather than configuration files, so a drop-in that re-enables what a file forbids
  is seen. That is the whole argument for the project.
- **789 OS-neutral controls across 9 Linux targets**: Debian 12 and 13, Ubuntu 22.04, 24.04 and
  26.04, RHEL 8, 9 and 10, Fedora. AlmaLinux and Rocky auto-detect to the RHEL profile of the same
  version. One control has one stable id and N standard references as tags; a standard is a view
  over one control set, never a duplicated control.
- **Multi-standard mappings**, sourced and never invented: CIS (per-OS benchmark version),
  ANSSI-BP-028 v2.0, NIST SP 800-53 Rev 5 and 800-171, PCI-DSS 4.0, DISA STIG, plus each control's
  SOCLE reference.
- Each control declares its **evidence type** (`effective-runtime`, `persistent-config`,
  `inventory-state`, `filesystem-state`), because a pass does not prove the same thing in each case,
  and a runtime pass is not a reboot-survivable one.
- A self-contained HTML report, chaptered by standard, with a grade, a severity breakdown and
  client-side standard and level selectors. Also JSON, SARIF, JUnit and CSV, and `--fail-under N`
  to turn the grade into a CI exit code.
- `scan --from <report.json>` re-grades an archived result with **no target, no transport and no
  engine**: the report names its own platform. The machine may be long gone, or never yours.

### Hardening

- `pavois harden plan` produces a reviewable YAML plan from a real scan, and `harden apply` runs it
  through Chef. Dangerous remediations are held back by default, and the engine never installs
  itself on a target without `--bootstrap-cinc`.
- `harden apply --reboot` proves the reboot happened by comparing the kernel `boot_id` before and
  after, then re-scans, so a setting that only holds until the next boot cannot pass silently.
- `pavois verify` attempts the forbidden action and confirms the protection actually holds, rather
  than re-reading the setting that was just written. `pavois rollback` reverts an applied plan.

### Evidence and exports

- `pavois bundle` packages a campaign (before and after scans, plan, reports, transition delta,
  manifest, checksums) into a tamper-evident directory, and `bundle verify` re-checks all of it.
  Signing is the operator's, under their own identity: Pavois never holds a key.
- `pavois oscal` publishes the baseline as **OSCAL 1.1.2**: a catalog grouped by domain, each
  control carrying its effective check, its per-OS CIS/STIG numbers and its norm links, plus one
  profile per OS, consumable by any GRC tool.
- `pavois diff` compares two scans or two plans: fixed, regressed, newly applicable, grade delta.
  `pavois rules` and `pavois norms` expose the rule base and the standard catalogue as JSON, and
  `pavois doctor` checks the environment before anything else does.

### How it is built

- One DRY source, `docs/reference/rules.yml`, one control per id, with 7 check templates
  (file_owner, package, sysctl, kconfig, service_disabled, mount_option, kmod_disabled) covering
  more than half the corpus. The 9 per-OS reference files and the `.rb` corpus are generated from
  it, never edited by hand.
- Release artifacts are pulled from the repository's GitHub releases: static binaries for linux and
  darwin on amd64 and arm64, `.deb` and `.rpm` packages, `checksums.txt`, a CycloneDX SBOM, a SLSA
  build-provenance attestation and a keyless Cosign signature. All three proofs are checkable
  without any access to this repository.

### Validated

- **Debian 12 and Debian 13**, end to end, on fresh VMs created by the published tooling: stock
  scan, plan, apply, reboot, re-scan, a second pass re-planned from the resulting state, and an
  evidence bundle verified at the end. `tools/golden_path.sh` is that campaign, runnable by anyone.
  Both finished with every automatic control passing.
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

[Unreleased]: https://github.com/stephrobert/pavois/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/stephrobert/pavois/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/stephrobert/pavois/releases/tag/v0.1.0
