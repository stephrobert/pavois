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

## [0.1.2] - 2026-09-17

Ten defects. Six were opened against 0.1.1 by a user working from a fresh VM, four more were found
by the harness written to close them, and not one is visible from inside a checkout, which is why
none was caught before shipping. The baseline is unchanged, so an 0.1.1 report stays comparable to
an 0.1.2 one.

### Fixed

- **`harden plan` could not run from a downloaded binary** (#286). The reference was read with
  `os.ReadFile` under `findRoot()`, and `findRoot()` falls back to the CURRENT DIRECTORY when it
  finds no `profiles/` above it. The path moved when you `cd`'d, which is the tell. So `scan`
  honoured the self-contained promise and `harden` did not: half the product was unreachable for
  anyone who installed from a release, and the error named an internal repository path rather than
  anything the reader could act on. The reference is now embedded like the rule corpus already was.
  The same defect reached three more commands the issue did not name: `rules`, `norms` and `oscal`
  all read the reference the same way, and the last two failed *worse* than `harden`, by succeeding
  with an empty catalogue.
- **`scan local --sudo` was refused by the engine** (#281), while `pavois doctor`, the README, the
  site and Pavois's own unprivileged-scan refusal all recommended that exact form. CINC is right to
  refuse: a local transport cannot elevate itself. `--sudo` states an intent, so on a local target
  Pavois now re-runs the command under sudo, says so, and hands the reports back to the user who
  asked for them.
- **A failed scan reported a second, misleading error** (#282). Any non-zero exit from the engine
  was treated as "controls are failing", so a refusal to run came back as a verdict and the caller
  then complained about a report file that was never written. Only 100 and 101 are verdicts now.
- **`--bootstrap-cinc` was silent on a local target** (#283). The flag whose purpose is "the engine
  is missing, install it" was unreachable in exactly that case, because the scan died on OS
  detection first with an error that did not mention the flag. It now says it applies to remote
  targets only, and where to get the engine.
- **`pavois --version` answered `unknown flag`** (#284), on a CLI whose own bug-report form asks for
  a version string. Fixed by [@Voyagerroc-Code](https://github.com/Voyagerroc-Code) in #287, the
  first outside contribution to this repository, and placed better than the version written here:
  in `version.go`'s `init()`, beside the variable and the subcommand that prints it, rather than
  split between the root command and `Execute()`.
- **The SSH failure hint recommended `--key` even when `--key` was passed** (#285), sending the
  reader back to their own command line instead of to the target that was refusing them. The hint
  is now chosen from whether a key was supplied and whether an agent is reachable.
- **`--out` meant a directory on `scan` and a file on `harden plan`**, so `--out ~/reports` answered
  `is a directory` on the second of two commands people run one after the other. `harden plan` now
  accepts a directory and creates the path.
- **`norms.yml` was read the same way** and was missed on the first pass at #286: `pavois norms`
  still answered `read norm catalogue: open /tmp/docs/reference/norms.yml`. Embedded too.
- **`harden apply` converged an EMPTY audit ruleset and reported success.** `audit.rules` and the
  per-OS kernel recipe were read under `findRoot()` **with the error discarded**, so a downloaded
  binary hardened a machine, skipped those two domains entirely, and told the operator it had
  worked. The worst of the family, because it did not fail: #286 at least stopped and said so. Both
  are embedded, and a read that fails now stops the apply.
- **`harden apply` could not target `local`** (#200). It invoked ssh and scp unconditionally, at ten
  places, so a local target meant `ssh -tt local …`: an attempt to reach a host literally named
  "local". Not even a clean failure, since a `Host local` entry in `~/.ssh/config` would have sent
  the converge to an arbitrary machine. A transport indirection now decides once, from the target,
  whether a command runs over ssh or here.
- **`sudo-noexec` left a host neither administrable nor auditable** (#288). `Defaults noexec`
  forbids a command run through sudo, and everything it spawns, from executing anything. Measured on
  a clean Ubuntu 24.04 against a control group: `sudo apt-get install` fails, and cinc-auditor is
  blocked on its first control, because auditing effective configuration means running `sshd -T`,
  `sysctl` and `systemctl show`. So a host carrying it cannot be audited through sudo at all,
  including for that very control, and that applies to any such scanner. The control is not dropped
  (it genuinely stops vi and less from spawning a shell, measured): it becomes `dangerous`, its
  remediation carves out the package managers per distribution, its check now requires a GLOBAL
  default instead of accepting any `Defaults ... noexec` line, and Pavois says what is wrong instead
  of `exit 126: no report produced`.

### Testing

- `tools/release/scenario.sh` (`mise run release:scenario`) is the complete first-run scenario on
  one disposable VM: install the binary, read what a machine with no engine is told, install the
  engine, scan from an unprivileged account, remediate from several directories. Every issue above
  has an assertion in it. It found the `--out` defect on its first run.
- `tools/doc_commands.mjs` makes the documentation the test input. The scenario installs the engine
  by running the block the install pages render, not a copy of it, with only the two substitutions
  the page itself tells the reader to make. `--check` also fails when the two languages would run
  different commands.
- `.claude/skills/vm-proof-harness` records the ladder of proof and the traps already paid for, so
  they are paid once.

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

[Unreleased]: https://github.com/stephrobert/pavois/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/stephrobert/pavois/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/stephrobert/pavois/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/stephrobert/pavois/releases/tag/v0.1.0
