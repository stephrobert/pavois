# Contributing to Pavois

Pavois is a community **compliance scanner**. Its heart is the **rule library**: InSpec controls
that audit a system's **effective configuration** (not its files), mapped to standards (CIS, ANSSI
BP-028, NIST, PCI-DSS, STIG) and tagged by level. That is where the project most needs the community.

Why not just read config files: a fixed file misses `Include` directives, drop-ins and the applied
state. Pavois queries the **resolved** state (`sshd -T`, `sysctl`, `systemctl show`, `nginx -T`). A
rule that reads a service's file instead of its effective config does not belong here.

## Ground rules (non-negotiable)

1. **Effective configuration, always.** For anything a service exposes, audit the resolved state.
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
| **Add or deepen a rule** *(most needed)* | add a control to `docs/reference/rules.yml` that audits **effective** state, with its standard mappings + level | grows the library — the core value |
| **Fill a thin domain** | the partial domains today are **firewall** (ruleset/zones), **logging** (remote forwarding, integrity), **time-sync**, **MAC** (custom SELinux/AppArmor). Deepen one. | turns "partial" into "delivered" |
| **Add an OS** | extend `rules.yml` `@os` keys + a `profiles/linux/<os>/` target | wider reach |
| **Fix / source a mapping** | cross-check a CIS/ANSSI/NIST/PCI/STIG ref against an authoritative source; correct it in `rules.yml` | accuracy, trust |
| **Enrich the site** | bilingual rule fiches, glossary terms, handbook pages under `site/src/content/` | the reference experience |
| **Improve the engine/CLI** | Go work under `go/` — see the roadmap items in Feature status | capability |

**A good rule contribution** audits effective config, has a neutral slug id, `impact`/`title`/`desc`,
a `tag domain:`, at least one **sourced** standard mapping, and per-standard level tags. It must be
**tested on a real target** and stay portable (`os.family`/`only_if` where needed).

## One check = one control, N standards

A single technical control usually belongs to several regulations. We do **not** duplicate it per
standard: it carries one **stable, standard-neutral id** (a `domain-object` slug) and all its
normative mappings as **tags**. A "standard" is a *view* — the HTML report lets the reader pick the
regulation and recomposes chapters and score client-side.

```ruby
control "ssh-permitrootlogin" do        # pavois id, neutral wrt standards
  impact 1.0
  title "SSH: root login disabled"
  desc  "A drop-in in sshd_config.d can re-enable root; we audit the effective " \
        "state via `sshd -T`, not the file."
  tag domain: "SSH"          # neutral chaptering
  tag cis:       "5.2.10"    # standard mappings (as many as apply)
  tag bp28:      "R36"
  tag 'pci-dss': "2.2.4"
  tag level_cis: "1"         # level per standard
  tag level_bp28: "minimal"
end
```

## The source of truth — how to add a rule

Controls are **not** edited as `.rb` files directly. The single DRY source is
[`docs/reference/rules.yml`](docs/reference/rules.yml) — one entry per control id, fields keyed `@os`
only where they differ. Everything downstream is generated:

```
docs/reference/rules.yml ──gen──▶ docs/reference/pavois-content/<os>.yml ──render──▶ profiles/linux/<os>/controls/*.rb
```

To add or change a control: edit `rules.yml` (effective check + standard mappings + level), then:

```bash
mise run gen          # render the 8 per-OS reference files from rules.yml
mise run regen        # rebuild the .rb corpus + OSCAL from the reference
mise run gen:verify   # CI guard: OS files match render(rules.yml)
mise run validate     # cross-validate CIS coverage against >= 2 authoritative sources
```

The `.rb` corpus and the OSCAL bundle are **derived artifacts** — git-ignored, rebuilt from source;
never commit them. After a fresh clone, run `mise run regen` once before scanning.

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

# Python tooling (tools/, test-vms/)
ruff check tools/ test-vms/ && ruff format --check tools/ test-vms/ && bandit -r tools/ test-vms/ -c pyproject.toml

# the actual tool, on a real target (effective config needs --sudo)
mise run build && ./go/pavois scan local --profile linux/ubuntu2404
```

Go follows the **go-production-engineer** standard: simple, idiomatic, explicit error handling (wrap
with `%w`), no needless abstraction, tests for meaningful behavior, documented public symbols.

In the HTML report, switch the **regulation** in the dropdown: your control must appear in the right
chapter of every standard it maps to, with its severity, mappings and effective-check detail.

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
