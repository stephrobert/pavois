<p align="center">
  <img src="site/public/brand/pavois-seal.svg" alt="Pavois" width="120">
</p>

<p align="center">
  <b>Effective Linux compliance &amp; hardening, over CINC / InSpec</b><br/>
  <sub>Audits the configuration your services <i>actually run</i> (<code>sshd -T</code>, <code>sysctl</code>, <code>systemctl</code>, <code>auditctl</code>), not just the files on disk. Maps each control to every applicable standard (CIS, ANSSI BP-028, NIST, PCI-DSS, STIG), grades it <b>A:E</b>, and hardens it as code.</sub>
</p>

<!-- A badge is a MEASUREMENT or it is decoration. The Scorecard one used to carry
     `&color=dc2626`, which overrides the colour shields.io computes from the score: a 6.9 and a 10
     rendered identically, in red, so the one badge whose job is to warn could not. The colour is
     the signal, and it is left alone, like dsoxlab and coucou do.
     There was also a static SLSA badge, hardcoded red, linking to the spec. It measured nothing and
     announced "build provenance" while no release existed. The provenance is real and verifiable,
     so it is stated where a reader can act on it: the install section prints
     `gh attestation verify`, which checks it against the public transparency log. -->
<p align="center">
  <a href="https://securityscorecards.dev/viewer/?uri=github.com/stephrobert/pavois"><img src="https://img.shields.io/ossf-scorecard/github.com/stephrobert/pavois?label=OpenSSF%20Scorecard" alt="OpenSSF Scorecard"></a>
  <a href="https://score.getplumber.io/github.com/stephrobert/pavois"><img src="https://score.getplumber.io/github.com/stephrobert/pavois.svg" alt="Plumber compliance score"></a>
</p>

<p align="center">
  <a href="https://github.com/stephrobert/pavois/actions/workflows/release.yml"><img src="https://img.shields.io/github/actions/workflow/status/stephrobert/pavois/release.yml?label=Build" alt="Build"></a>
  <a href="https://github.com/stephrobert/pavois/releases"><img src="https://img.shields.io/github/v/release/stephrobert/pavois" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/Go-1.26-00ADD8?logo=go&logoColor=white" alt="Go 1.26">
  <img src="https://img.shields.io/badge/engine-CINC%2FInSpec-4a90d9" alt="CINC / InSpec">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License Apache-2.0"></a>
</p>

<p align="center">
  <a href="https://pavois.dev">Website</a> •
  <a href="https://pavois.dev/en/handbook/">Handbook</a> •
  <a href="https://pavois.dev/en/rules/">Controls</a> •
  <a href="https://pavois.dev/en/downloads/">OSCAL</a> •
  <a href="https://github.com/stephrobert/pavois/issues">Issues</a>
</p>

---

## 🛡️ What is Pavois?

Pavois is a Linux **compliance scanner and hardening tool** built on **CINC Auditor** (the
open-source build of Chef InSpec). It competes with OpenSCAP and Lynis, with one decisive
difference: it audits the **effective configuration** of a running host, not the text of files.

- **Effective, not file-based.** A control on a service reads the resolved state: `sshd -T`,
  `sysctl`, `systemctl show`, `auditctl -l`. It catches the `Include`s and drop-ins a file read
  misses, where a permissive override silently defeats a stricter main config.
- **One control, every applicable mapping.** A single effective-config assertion carries all its standard mappings:
  **CIS**, **ANSSI BP-028**, **NIST** (800-53 / 800-171), **PCI-DSS** and **DISA STIG**. One
  neutral control, every applicable mapping, never a duplicated rule.
- **A:E grade, transparent.** A published scoring formula (failure-weighted, critical-capped),
  computed identically in the CLI and the HTML report.
- **Harden as code.** `pavois harden` plans the fixes, you opt in per rule, and a native Chef run
  converges them. No blind shell script.
- **A qualified verdict.** A PASS states what it proves: **running now** vs **reboot-survivable**.
  A runtime-only pass caps the grade under A until persistence is proven. See [the qualified
  verdict](https://pavois.dev/en/handbook/qualified-verdict/).
- **Nothing installed behind your back.** Runs `cinc-auditor` natively over `local`, `ssh://` or
  `docker://` targets, using your own `~/.ssh/config`. No agent, no daemon, nothing left running.
  The fast `--on-target` mode needs the engine present on the target: if it is missing Pavois says
  so and stops, and only installs it when you pass `--bootstrap-cinc`.

<p align="center">
  <a href="https://pavois.dev"><img src="site/public/media/harden-demo-poster.jpg" alt="Pavois harden demo" width="680"></a>
</p>

## 🚀 Install

**Pavois is a single static binary.** The rule corpus is embedded (`go:embed`), so there is nothing
to generate, no toolchain to install and nothing to compile: download it, verify it, scan.

> **Building from source is for contributors, not for users.** It is documented further down, and
> it is not a second way to install the tool. If you are here to use Pavois, what you want is the
> binary below.

### Install the binary

Binaries are pulled from this repository's [releases](https://github.com/stephrobert/pavois/releases):
a static binary per platform (linux and darwin, amd64 and arm64), `.deb` and `.rpm` packages,
`checksums.txt`, a CycloneDX SBOM, a SLSA build provenance and a keyless Cosign signature. Verify
before running it: a hardening tool you did not verify is a strange way to start hardening.

```bash
gh release download --repo stephrobert/pavois \
  --pattern 'pavois-linux-amd64' --pattern 'checksums.txt'   # no tag: the latest release
sha256sum --ignore-missing --check checksums.txt
gh attestation verify pavois-linux-amd64 --repo stephrobert/pavois   # SLSA build provenance
chmod +x pavois-linux-amd64
./pavois-linux-amd64 doctor          # rule corpus: embedded in this binary
./pavois-linux-amd64 scan local --sudo
```

### Build from source (contributors)

You need this if you contribute to Pavois. It is not how the tool is meant to be installed, and it
never will be: the build pulls a pinned Go, Node and Python toolchain, and regenerates artifacts
that a release binary already carries inside it.

The repository ships the **source of truth only** (`docs/reference/rules.yml` + the enriched site
content). The InSpec corpus (`.rb`) and the OSCAL bundle are **derived artifacts**: they are not
committed, they are regenerated from the reference. So a from-source setup is build, then regen:

```bash
git clone https://github.com/stephrobert/pavois.git
cd pavois
mise trust && mise install   # pinned Go / Node / Python toolchain
mise run build               # compile the binary -> go/pavois
mise run regen               # rebuild the rule corpus + OSCAL from docs/reference/
```

`mise run regen` runs `gen` (rules.yml → per-OS reference) → `render` (→ the `.rb` corpus the
scanner executes) → `oscal` (→ the OSCAL bundle). Pavois never installs CINC Auditor on its own:
put `cinc-auditor` on the scanning host yourself (`pavois doctor` prints the omnitruck command when
it is missing). Without it, `ssh://` and `docker://` targets fall back to the pinned CINC container,
and `local` refuses (a container cannot audit its host). On the target side, `--on-target` needs the
engine there too: Pavois stops and says so, and installs it only when you pass `--bootstrap-cinc`.

### First scan in 5 minutes

The shortest path, auditing the current host (effective config needs root):

```bash
git clone https://github.com/stephrobert/pavois.git && cd pavois
mise trust && mise install && mise run build && mise run regen
./go/pavois doctor                           # is everything ready?
./go/pavois scan local --sudo --format html  # audit this host, A:E grade
./go/pavois serve                            # browse reports at http://localhost:8098
```

Once the first release ships, swap the build for the signed binary (Option A). For a remote
target: `scan user@host --key ~/.ssh/id_ed25519 --sudo`.

> **`--key` is not optional, even when `ssh user@host` works.** Pavois reaches the target through
> the engine's SSH transport, which does **not** read `~/.ssh/config` and does **not** fall back to
> `~/.ssh/id_ed25519` the way the `ssh` command does. Omit it and the run stops at
> `could not reach or identify user@host`, on a host you can log into by hand a second later.
> Pass `--key <path>`, or add the key to `ssh-agent`.

## ⚙️ How it works

```bash
# 0. Check the environment is ready (CINC engine, sudo, SSH, OS, rule corpus)
pavois doctor

# 1. Audit a host (effective config needs sudo; the OS profile is auto-detected)
pavois scan user@host --key ~/.ssh/id_ed25519 --sudo

# 2. Plan the fixes, opt in per rule, converge a native Chef run, re-scan
pavois harden plan user@host --key ~/.ssh/id_ed25519 --sudo
#    every gap is written `apply: false`: flip the ones you want to `apply: true`.
#    a fresh host has a few hundred, so --enable arms them in one go:
#      --enable auto   every gap an apply can actually close (skips the dangerous ones,
#                      and the ones needing a partition, a kernel rebuild or a human)
#      --enable all    also the dangerous ones, still unacknowledged
#    a rule with a `danger:` line can brick/lock out the host: read it, then set
#    `acknowledged: true` on that item (or pass --i-understand-danger) or apply refuses it
pavois harden apply hardening-plan-debian12.yml --key ~/.ssh/id_ed25519 --reboot --scan

# 2b. CONVERGE: one apply is not enough, and that is not a defect.
#     Hardening MUTATES the machine, so it creates gaps the same pass cannot close: installing
#     `at` creates /etc/at.deny, which another control wants absent; pulling in postfix brings a
#     banner that names the distribution; sssd ships an AppArmor profile in complain mode.
#     Measured on a fresh Debian 12: pass 1 armed 211 gaps, pass 2 armed 37, of which 10 existed
#     only because pass 1 had installed the software they audit.
#     Re-plan from a CURRENT scan (never replay the old plan: it describes a machine that is gone)
#     and apply again, until a pass has nothing left to do. Two to three passes in practice.
pavois harden plan user@host --key ~/.ssh/id_ed25519 --sudo --enable auto
pavois harden apply hardening-plan-debian12.yml --key ~/.ssh/id_ed25519 --reboot --scan

# 3. Build a before/after campaign report (grade delta + transition matrix)
pavois diff before.json after.json --html campaign.html --json campaign.json

# 4. Package tamper-evident evidence, audit-ready once signed (before/after, plan, reports, manifest + checksums)
pavois bundle before.json after.json --plan hardening-plan-debian12.yml --report campaign.html

# 5. Serve the HTML reports
pavois serve   # http://localhost:8098
```

The scan prints the deviations by severity and the **A:E grade**, and writes an HTML report. With
`--reboot`, harden reboots the target and re-scans, so a pass in that report is **reboot-proven**; it
also writes a **reboot-proof artifact** (the boot_id before and after, proving the re-scan ran on a
fresh boot) that you can fold into the evidence bundle (`bundle --reboot-proof`).
`--format sarif|junit|json|csv|html|oscal` and `--fail-under <points>` make the grade a CI gate
(`oscal` emits schema-valid OSCAL 1.1.2 assessment-results, see [OSCAL](#-oscal)).

Every scan also prints a **posture breakdown** by remediation class (`auto`, `manual`, `dangerous`,
`install-time`, `kernel-build`) and a **remediable posture grade**, the A:E formula recomputed over
only the controls fixable on a running host (it excludes install-time and kernel-build), so an
unfixable separate partition or a kernel `CONFIG_*` does not mask what you can actually remediate.

`pavois diff` turns two scans into a **campaign report**: the grade delta plus the full transition
matrix (failed → passed, newly-applicable, still-failing, and any **regressions**). It shows every
control's before/after state, so a result cannot be dismissed as a moved denominator when the
baseline widens the applicable set. `--html` writes a self-contained report; `--json` the structured
delta for an evidence bundle.

`pavois bundle` packages a campaign into a tamper-evident **evidence bundle**: the before/after scans,
the plan that was applied, the reports, the reboot proof, the transition delta, plus a `manifest.json`
(tool + ruleset version, **pavois binary digest**, target, grade delta) and a `checksums.txt`. You then
**sign `checksums.txt` with your own identity** (`cosign sign-blob` or `gpg --detach-sign`): pavois does
not own the signing key, the auditor's trust is in your KMS/OIDC identity. **`pavois bundle verify <dir>`**
re-checks every artifact's SHA-256, the manifest digest, and the signature if present (exit non-zero on
any tampering; `--require-signature` to also fail when unsigned), turning the package into tamper-evident evidence, opposable once signed under an accepted trust policy,
audit-ready evidence.

```console
$ pavois bundle verify evidence/ --require-signature
  manifest.json        digest OK
  checksums.txt        12/12 artifacts match
  signature            verified (cosign, identity bob@example.org)
bundle OK: tamper-evident and signed
# exit 0; non-zero on any checksum/manifest mismatch or (with --require-signature) a missing signature
```

| Command | Does |
|---------|------|
| `scan` | Audit a target's effective config, grade A:E |
| `harden plan` / `apply` | State-aware Chef hardening, opt-in per rule, `--reboot --scan` |
| `diff` | Before/after campaign report: transition matrix, regressions, grade delta (`--html` / `--json`) |
| `bundle` / `bundle verify` | Package tamper-evident evidence (scans + plan + reports + manifest + checksums), audit-ready once signed, then verify integrity + signature |
| `verify` | Behavioral check: attempt the forbidden action, confirm the protection holds |
| `oscal` | Publish the baseline as OSCAL (catalog + per-OS profiles) |
| `serve` | Browse the HTML reports |

## 📐 One control, every applicable mapping

Each control declares the evidence it gathers and maps to where each applicable standard places the
requirement. A mapping is an anchored, cross-validated **cross-reference**, not a claim of
equivalence. Browse the [control explorer](https://pavois.dev/en/rules/) and the per-standard
views: [CIS](https://pavois.dev/en/standards/cis/) · [ANSSI BP-028](https://pavois.dev/en/standards/bp28/)
· [NIST](https://pavois.dev/en/standards/nist/) · [PCI-DSS](https://pavois.dev/en/standards/pci-dss/)
· [STIG](https://pavois.dev/en/standards/stig/).

## 🔒 Supply chain

Pavois holds itself to the posture it audits:

- **SLSA build provenance** on every release binary (`actions/attest-build-provenance`); verify
  with `gh attestation verify`.
- **OpenSSF Scorecard** on the repository.
- **Plumber-validated CI**: our own workflows are scanned by [Plumber](https://getplumber.io)
  against a trust policy (`.plumber.yaml`): actions pinned by commit SHA, least-privilege
  permissions, no dangerous triggers, no `write-all`, CVE / archived-action checks.
- **Trivy dependency audit** (pinned) over the Go and npm locks; a fixable HIGH/CRITICAL blocks CI.
- **14-day dependency quarantine**: Dependabot `cooldown` delays adopting a new dependency version
  until it has aged 14 days (security fixes bypass it).

## 📦 OSCAL

Pavois speaks **OSCAL 1.1.2** on both sides of an audit:

- **The standard**: the control catalogue publishes as an OSCAL **catalog** (+ per-OS
  **profiles**), consumable by any OSCAL-aware GRC tool. Each control carries its evidence type and
  the qualified verdict (`proves-running` / `proves-persistent` / `proves-reboot-survivable`).
  Derived artifact: `mise run oscal` regenerates it.
- **The run outcome**: `pavois scan --format oscal` emits OSCAL **assessment-results**
  (reviewed-controls + observations + findings), with the run provenance (tool + ruleset digests,
  target, timestamp, scope) stamped into the metadata. Passes, failures, not-applicable **and
  not-evaluated** all travel, so a coverage gap can never read as a pass.

**The output is schema-valid and independently verifiable**: not a claim, a check you can run
yourself against the official [NIST OSCAL 1.1.2 schema](https://github.com/usnistgov/OSCAL/releases/tag/v1.1.2):

```console
$ pavois scan user@host --sudo --format oscal > assessment-results.json
# validate against the official OSCAL 1.1.2 schema (either tool):
$ oscal-cli assessment-results validate assessment-results.json
$ check-jsonschema --schemafile oscal_assessment-results_schema.json assessment-results.json
ok -- validation done
```

The shared `assessment` model and OSCAL renderer live in
[scankit](https://github.com/stephrobert/scankit); pavois and its sibling scanners all emit the
same conformant form. See [Downloads](https://pavois.dev/en/downloads/).

## 🗺️ Coverage

Pavois audits the effective configuration of a running Linux host across 9 OS targets, and is
explicit about its edges: some domains (firewall ruleset, log forwarding, MAC policy depth) are
shallow today. The honest [coverage matrix](https://pavois.dev/en/handbook/coverage/) names what is
deep and what is not.

**Two of those nine have been proven end to end.** Debian 12 and Debian 13 each go through the full
campaign in `tools/golden_path.sh` on a fresh VM: scan, plan, apply, reboot, re-scan, a second pass
re-planned from the resulting state, and an evidence bundle verified at the end. The other seven are
curated and statically validated, but no campaign has been run on them, so treat them as
experimental and say what you find. That distinction is deliberate: "9 systems supported" and
"9 systems proven" are not the same sentence, and only one of them is true.

## 🤝 Contributing

The **rule library** is where the project most needs help: **[CONTRIBUTING.md](CONTRIBUTING.md)**
has a "Where to help" table mapping each intent (add a rule, deepen a thin domain, add an OS, source
a mapping…) to a concrete action. How the code fits together: **[ARCHITECTURE.md](ARCHITECTURE.md)**.
By participating you agree to the **[Code of Conduct](CODE_OF_CONDUCT.md)**. Report security issues
privately via **[SECURITY.md](SECURITY.md)**.

## 📄 License & attribution

Apache-2.0 (see [LICENSE](LICENSE)). Control definitions derive from
[ComplianceAsCode/SSG](https://github.com/ComplianceAsCode/content) (BSD-3) and are cross-validated
against ansible-lockdown. CIS Benchmarks, PCI DSS, STIG and NIST are trademarks of their respective
owners; Pavois is not affiliated with or endorsed by them. NIST/STIG content is U.S. Government
public domain.
