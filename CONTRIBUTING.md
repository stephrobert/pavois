# Contributing to Pavois

Pavois is a community **compliance scanner**. Its heart is the **rule library**: InSpec controls
that audit a system's **effective configuration** (not just its files), mapped to standards (CIS, ANSSI
BP-028, NIST, PCI-DSS, STIG) and tagged by level. That is where the project most needs the community.

Why not just read config files: a fixed file misses `Include` directives, drop-ins and the applied
state. Pavois queries the **resolved** state (`sshd -T`, `sysctl`, `systemctl show`, `auditctl -l`). A
rule should read a service's resolved view (`sshd -T`, `sysctl`...) when it exposes one; otherwise declare the right evidence type (persistent-config, inventory-state, filesystem-state).

## Ground rules (non-negotiable)

1. **Effective configuration first.** When a service exposes a resolved view, audit that; otherwise declare the correct evidence type (persistent-config, inventory-state, filesystem-state).
2. **100% CINC/InSpec.** Pavois never uses OpenSCAP as an engine.
3. **One check, N standards.** Never duplicate a control per standard (see below).
4. **Tested before merge.** Every change runs the real quality gates locally (see below).
5. **Pinned + reproducible.** Tool versions pinned via `mise`; CI Actions pinned by commit SHA; no
   dependency lifecycle scripts run on install.

## Where to help — how to improve the tool

Pick the track that fits you. Each control's gaps are honest and published: see
[What Pavois covers](https://pavois.dev/en/handbook/coverage/) and
[Feature status](https://pavois.dev/en/handbook/feature-status/) (delivered / partial / roadmap).

| You want to… | Do this | Impact |
|---|---|---|
| **Add or deepen a rule** *(most needed)* | add a control to `docs/reference/rules.yml` that audits the **strongest available evidence** (and declares its evidence type), with its standard mappings + level | grows the library — the core value |
| **Fill a thin domain** | the partial domains today are **firewall** (ruleset/zones), **logging** (remote forwarding, integrity), **time-sync**, **MAC** (custom SELinux/AppArmor). Deepen one. | turns "partial" into "delivered" |
| **Add an OS** | extend `rules.yml` `@os` keys + a `profiles/linux/<os>/` target | wider reach |
| **Fix / source a mapping** | cross-check a CIS/ANSSI/NIST/PCI/STIG ref against an authoritative source; correct it in `rules.yml` | accuracy, trust |
| **Enrich the site** | bilingual rule fiches, glossary terms, handbook pages under `site/src/content/` | the reference experience |
| **Improve the engine/CLI** | Go work under `go/` — see the roadmap items in Feature status | capability |

**A good rule contribution** audits the strongest available evidence and declares the correct evidence type (effective-runtime, persistent-config, inventory-state or filesystem-state), has a neutral slug id, `impact`/`title`/`desc`,
a `tag domain:`, at least one **sourced** standard mapping, and per-standard level tags. It must be
**tested on a real target** and stay portable (`os.family`/`only_if` where needed).

## One check = one control, N standards

A single technical control usually belongs to several regulations. We do **not** duplicate it per
standard: it carries one **stable, standard-neutral id** (a `domain-object` slug) and all its
normative mappings as **tags**. A "standard" is a *view* — the HTML report lets the reader pick the
regulation and recomposes chapters and score client-side.

You edit **YAML** in `docs/reference/rules.yml` (never the `.rb`, which is generated):

```yaml
ssh-disable-root-login:               # neutral pavois id, standard-agnostic
  title: Disable SSH Root Login
  domain: SSH                         # neutral chaptering
  evidence_type: effective-runtime    # 1 of 4 types — auto-filled by `gen:evidence`, omit to let it classify
  severity: critical                  # impact 1.0
  impact: 1.0
  applicable_os: [debian12, ubuntu2404, rhel9]   # ... and the rest
  check:                              # the EFFECTIVE check: sshd -T, never the file
    - describe command('sshd -T') do
    - "  its('stdout') { should match(/^permitrootlogin\\s+no$/i) }"
    - end
  norms:                              # every standard that applies (value can be keyed @os)
    bp28: R33
    cis: "5.1.20"
    nist: [AC-17(a), IA-2(5)]
  ssg: sshd_disable_root_login        # SSG cross-reference (drives tools/coverage_gap.py)
  levels: { cis: "1", bp28: intermediary }   # level per standard
```

`mise run gen && mise run render` turn this single entry into the per-OS reference and the InSpec
`.rb` the scanner runs. Fields that differ per OS are keyed `@os` (e.g. a CIS number that changed
between releases). The generated `.rb` for the control above looks like this (do **not** edit it):

```ruby
control "ssh-disable-root-login" do
  impact 1.0
  title "Disable SSH Root Login"
  tag domain: "SSH"
  tag cis: "5.1.20"
  tag bp28: "R33"
  describe command("sshd -T") do
    its("stdout") { should match(/^permitrootlogin\s+no$/i) }
  end
end
```

**Conventions for a new control:**

- **`domain`** — reuse an existing neutral domain, do not invent one. The canonical list (33) is
  [`site/src/data/domain-labels.ts`](site/src/data/domain-labels.ts) (e.g. `SSH`, `Sudo`,
  `Kernel & network (sysctl)`, `Audit (auditd)`, `Packages`, `Mounts`...).
- **`ssg`** — the SSG rule short id you map. To find what that rule actually checks (so your
  effective check matches its intent), read the datastream and the gap tooling:
  ```bash
  mise run coverage:gap -- --os debian12 --datastream ssg-debian12-ds.xml   # lists unmapped SSG rules + titles
  mise run rule:show -- --os debian12 --id <existing-id>                     # a similar control's check + mappings
  ```
  The SSG datastream (`ComplianceAsCode/content` release) holds the rule's description, rationale and
  OVAL, the source of truth for what to assert.

## The source of truth — how to add a rule

Controls are **not** edited as `.rb` files directly. The single DRY source is
[`docs/reference/rules.yml`](docs/reference/rules.yml) — one entry per control id, fields keyed `@os`
only where they differ. Everything downstream is generated:

```
docs/reference/rules.yml ──gen──▶ docs/reference/pavois-content/<os>.yml ──render──▶ profiles/linux/<os>/controls/*.rb
```

To add or change a control: edit `rules.yml` (effective check + standard mappings + level), then:

```bash
mise run gen           # render the 8 per-OS reference files from rules.yml
mise run gen:evidence  # (re)classify evidence_type from the check, written back into rules.yml
mise run gen:reboot    # (re)classify reboot_survivable (the persistence axis of the verdict)
mise run gen:socle     # assign the SOCLE-<DOM>-<FAM>-<N> ref to new controls
mise run regen         # rebuild the .rb corpus + OSCAL from the reference
mise run gen:verify    # CI guard: the 8 OS files match render(rules.yml)
mise run validate          # cross-validate CIS coverage against >= 2 authoritative sources
mise run validate:mappings # cross-validate NIST + PCI-DSS tags vs ciso-assistant
mise run validate:bp28     # validate ANSSI-BP-028 tags against the official v2.0 PDF
```

`evidence_type` and `reboot_survivable` are **derived**, not hand-written: `gen:evidence` reads the
check (the InSpec code never lies about what it reads) and writes `evidence_type` into `rules.yml`,
`gen:reboot` does the same for `reboot_survivable`. Set them by hand only to override the classifier.
`regen` does **not** run these passes, run them yourself after editing a check.

The `.rb` corpus and the OSCAL bundle are **derived artifacts** — git-ignored, rebuilt from source;
never commit them. After a fresh clone, run `mise run regen` once before scanning.

### Fix a rule in minutes

Pick the smallest loop for your change. The `rule:*` tasks wrap `pavois rules --id <id>` and
`pavois scan <target> --controls <id>` so you iterate on **one** control, never the full corpus.

**1. Mapping fix only** (a wrong/missing `cis:`/`bp28:`/`ssg:` reference): no scan needed.

```bash
mise run rule:show -- --os debian12 --id ssh-disable-root-login   # see the entry + its mappings
# edit norms:/ssg: in docs/reference/rules.yml
mise run gen && mise run validate:mappings                        # regenerate + cross-check the mapping
```

**2. Threshold / check fix**: render, then run just this control against any target (`local` is fastest).

```bash
# edit check:/remediation: in docs/reference/rules.yml
mise run gen && mise run render                                   # per-OS reference + .rb corpus
mise run rule:test -- local --sudo --controls ssh-disable-root-login   # one control, one target
```

**3. New control**: add an id with `domain`, `evidence_type`, `severity`, `check`, `norms`, `ssg`,
then `mise run gen:verify` and `mise run coverage:gap` to confirm it closes an SSG gap.

## Development setup

```bash
mise install          # pinned toolchain: Go, Node, Python, gh, golangci-lint, ruff, trufflehog
pre-commit install    # quality + secret hooks on every commit
```

## Debugging a hardened test VM

`harden apply --reboot` against a throwaway VM can leave it unbootable (a remediation that breaks an
early-boot mount drops the guest to **emergency mode**, and a locked root makes the console useless).
When you test remediations on an Incus VM:

- **Snapshot before applying**, so you can roll back: `incus snapshot create <vm> preharden` /
  `incus snapshot restore <vm> preharden`.
- **Diagnose without blind reboots.** `harden apply <plan> --dry-run` prints the full Chef recipe;
  or apply **without** `--reboot` and inspect the converged state (`/etc/fstab`,
  `/boot/grub/grub.cfg`, `systemctl --failed`) before rebooting.
- **VM up but unreachable?** `incus exec <vm> -- …` runs commands without SSH. If it fails with
  `VM agent isn't currently running`, the OS never finished booting (a brick), not just SSH.
- **See the boot.** `incus console --show-log` is container-only; for a VM, capture the live serial
  console with a pseudo-TTY: `timeout 14 script -qec 'incus console <vm>' /dev/null </dev/null`
  (detach with `<ctrl>+a q`). It shows emergency mode, a panic, or a hanging start job.
- **Read the failed boot's journal offline** (the reliable way: no scrollback or sulogin needed; the
  harden sets journald `Storage=persistent`, so `/var/log/journal` survives). For a ZFS pool:
  ```bash
  incus stop <vm> --force
  Z=<pool>/virtual-machines/<vm>.block      # incus storage list; zfs list -t volume
  sudo zfs set volmode=dev "$Z"             # a stopped VM's zvol is volmode=none
  sudo kpartx -av /dev/zd0                  # maps /dev/mapper/zd0p2 (the ext4 root; p1 = EFI)
  sudo mount -o ro /dev/mapper/zd0p2 /mnt/vm
  sudo journalctl -D /mnt/vm/var/log/journal -b 0 -p err | grep -iE 'Dependency failed|Failed to mount|emergency'
  sudo umount /mnt/vm; sudo kpartx -d /dev/zd0; sudo zfs set volmode=none "$Z"   # cleanup
  ```
  (A `dir` pool: `losetup -fP <root.img>`; qcow2: `qemu-nbd`.) **Lesson:** a one-way "disable" sysctl
  like `kernel.modules_disabled=1` must be applied late (a systemd oneshot ordered
  `After=local-fs.target`), never in a boot-time `sysctl.d` drop-in, or it bricks the EFI mount.

## Quality gates (run before opening a PR)

CI enforces all of these; run them locally first.

```bash
# Go binary (go/)
cd go && gofmt -l . && go vet ./... && go build ./... && go test -race ./... && golangci-lint run ./...
govulncheck ./...

# Python tooling (tools/) — test-vms/ is local-only (gitignored), lint it yourself if you touch it
ruff check tools/ && ruff format --check tools/ && bandit -r tools/ -c pyproject.toml

# the actual tool, on a real target (effective config needs --sudo)
mise run build && ./go/pavois scan local --profile linux/ubuntu2404
```

Go follows the **go-production-engineer** standard: simple, idiomatic, explicit error handling (wrap
with `%w`), no needless abstraction, tests for meaningful behavior, documented public symbols.

### No rule change ships without a real scan

**Non-negotiable.** Any change to `rules.yml` that affects what a target audits, a **new control**,
a **remediation**, **or extending `applicable_os`** to a new OS, must be verified by a **real
`pavois scan`** on the concerned VM before the PR is mergeable. The control must come out **PASS**,
or its `harden apply` must make it PASS. `validate` / `validate:mappings` are **static** checks and
**never** substitute for the scan: an `applicable_os` extension without a working remediation
silently adds a permanent FAIL (a regression against "0 failing"). No PR merged on static validation
alone.

### Remediation changes: full-apply, zero regression

Any change to a **remediation** (or a check it interacts with) must pass a full hardening campaign
on a throwaway VM (Incus or Proxmox), with **every rule enabled**:

```bash
pavois scan <vm> --sudo --on-target                 # baseline report (before)
pavois harden plan <vm> --sudo                       # then flip EVERY `apply:` to true in the plan
pavois harden apply hardening-plan-<os>.yml --reboot --scan
pavois diff <before>.json <after>.json               # transition matrix
```

Two hard rules:

- **Enable all rules** (`apply: true` everywhere). A remediation must never break another control:
  applying everything at once is the only way to catch cross-control damage.

> **Always apply a FULL plan (the whole `harden plan` output), never a hand-made subset.**
> Aggregated remediations — sshd (`/etc/ssh/sshd_config.d/99-pavois.conf`), sysctl
> (`zz-pavois.conf`), kernel cmdline, keyval drop-ins — are rewritten **wholesale** on every
> apply. `harden apply` keeps them complete only by re-emitting the *compliant* sibling controls
> too — which requires those controls to be **present in the plan**. Apply a plan that contains
> only a subset (e.g. a quick test plan with 3 rules) and the drop-in is regenerated **without the
> missing controls**, silently regressing dozens of them (a subset sysctl plan wiped ~55 sysctls;
> a subset sshd plan re-enabled root login). For iteration use `scan --controls <id>` to check one
> control, but any real `harden apply` must run the full generated plan.
- **Zero regression.** No control may transition **passed → failed**. Example this exists to catch:
  a remediation wrote `/etc/audit/rules.d/99-pavois.rules` world-readable and failed the *separate*
  `fileperm-etc-audit-rulesd` control. If your change regresses any control, it is not ready.

The target is **0 failing** on a fresh host. A control that legitimately cannot converge must be made
**N/A** (topology: separate partitions; virtualized: `iommu=force`; build-time: `kconfig-*` on a
stock kernel, see the [hardened-kernel recipe](docs/remediation/hardened-kernel-debian12.md)) or a
documented **manual** remediation, never left silently failing.

In the HTML report, switch the **regulation** in the dropdown: your control must appear in the right
chapter of every standard it maps to, with its severity, mappings and effective-check detail.

### Dangerous remediations: explain the brick, gate the apply

A remediation that can **brick or lock out** the host (loses boot, disk, network, or privilege
escalation) must carry a `danger:` field in `docs/reference/rules.yml` — a short, specific English
sentence stating *what* breaks and *the precondition* to avoid it. Examples already in the corpus:
`cmdline-iommu-force`, `grub-password`, `kmod-loading-disabled`, `sudo-require-authentication`,
`sudo-remove-no-authenticate`, `sudo-require-reauthentication`, `mount-var-noexec`.

The field flows everywhere automatically: `gen.py` propagates it to the per-OS files, the corpus
renders it as `tag danger:`, the scan report shows it as a red **⚠ Danger** banner on the control,
and `harden plan` writes it on the item next to `acknowledged: false`.

`harden apply` **refuses to converge** any enabled item that has a `danger:` unless the risk is
acknowledged: either per item (`acknowledged: true` in the plan) or run-wide (`--i-understand-danger`).
Never ship a brick-prone auto remediation without a `danger:` line — the gate depends on it.

### Firewall and SSH access are plan-configurable

`firewall-default-deny` defaults to a **native nftables** ruleset (`choose: nftables`), not ufw.
On a **hardened kernel** (`kernel.modules_disabled=1`, e.g. the [KSPP build](docs/remediation/hardened-kernel-debian12.md))
this is the only firewall that reliably comes up: nftables needs only the built-in `nf_tables`
inet path, whereas ufw/iptables-restore pulls in a long tail of legacy `xt_*` match modules and a
single missing one makes the restore fail atomically → empty chains under `policy DROP` → **instant
SSH lockout** (learned the hard way; recover offline with `virt-customize -a <disk> --run-command 'ufw --force disable'`).

Because a default-deny firewall and a user/group SSH restriction can lock you out, both are **scoped
from the plan** (they default to open so a plan without them never bricks access):

- `ssh_allow_from: [cidr, …]` on `firewall-default-deny` — restrict SSH to those sources.
- `ssh_allow_users: [name, …]` / `ssh_allow_groups: [name, …]` on `misc-sshd-limit-user-access` —
  enforce sshd `AllowUsers`/`AllowGroups` (otherwise the control stays a manual, site-specific stub).
  **The list must include the account you connect as**, or you lock yourself out.

## Pull-request workflow

- `main` is protected — work on a **feature branch** and open a PR.
- Commits follow **[Conventional Commits](https://www.conventionalcommits.org/)**
  (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `build`; optional scope; imperative).
- The PR must pass every check: Go + Python quality, **CodeQL** (Go/Python/JS SAST),
  **dependency-review**, **secret scan** (TruffleHog), Trivy, OpenSSF Scorecard, Plumber.
- Keep changes focused; update tests and docs with the code; remove dead code.

## More

- Security issues: **do not** open a public issue — see [SECURITY.md](SECURITY.md).
- How the code fits together: [ARCHITECTURE.md](ARCHITECTURE.md).
- By participating you agree to our [Code of Conduct](CODE_OF_CONDUCT.md).
