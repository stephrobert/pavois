# Architecture

How Pavois is built and how the pieces fit. For contribution mechanics see
[CONTRIBUTING.md](CONTRIBUTING.md).

## What Pavois is

A **compliance scanner** built on **CINC Auditor** (the open-source build of Chef InSpec). It is a
native-first concurrent to OpenSCAP and Lynis, with two deliberate differences:

- It audits the **effective configuration** (the resolved runtime state), not config files.
- It reports **by standard chapter** (ANSSI BP-028, CIS, …) with a score, per-severity breakdown,
  per-rule detail and client-side filters — a structured report, not a flat checklist.

The shipped binary is **100% Go** and **100% CINC/InSpec**. OpenSCAP is never used as an engine
(it is blind to `Include`, drop-ins and applied config — the whole reason Pavois exists).

## The differentiator: effective configuration

Any control touching a service queries the resolved state, never the file:

| Subsystem | Pavois reads | Not |
|---|---|---|
| SSH | `sshd -T` | `/etc/ssh/sshd_config` |
| Kernel | `sysctl -a` | `/etc/sysctl.conf` |
| systemd | `systemctl show <unit>` | unit files |
| Nginx / Apache | `nginx -T` / `apachectl -S` | site files |

A control that reads a file misses drop-ins and `Include`s → false negative. These commands need
root, so service-touching scans run with `--sudo` (passed through to CINC).

## Repository layout

```
go/                         the pavois binary (Go)
  cmd/                      cobra CLI: scan | harden | report | serve | oscal | verify | version
  internal/engine/          engine choice + cinc-auditor execution (native/docker), transports
  internal/audit/           InSpec JSON -> findings, standard/level filtering, A–E grade
  internal/render/          chaptered, multi-standard HTML report (CSS/JS embedded via //go:embed)
docs/reference/rules.yml    SOURCE OF TRUTH — one control/id, fields keyed @os only where they differ
docs/reference/pavois-content/<os>.yml   8 per-OS files GENERATED from rules.yml
profiles/linux/<os>/controls/            InSpec corpus RENDERED from the per-OS reference (.rb)
tools/                      offline Python tooling (generation, validation, norm-studio MCP)
site/                       bilingual (FR/EN) Astro site — the public reference
```

## The Go binary

`main` stays thin; the CLI delegates to reusable internal packages.

1. **`cmd`** wires the cobra commands and the CI-meaningful exit codes.
2. **`internal/engine`** picks the engine (`--engine auto` = native if `cinc-auditor`/`inspec` is
   present, else docker) and runs it over the chosen transport, capturing the InSpec JSON.
3. **`internal/audit`** turns that JSON into findings, filters by the selected standard and level,
   and computes the A–E grade (with the caps below).
4. **`internal/render`** produces the self-contained HTML report — one `<select>` for the regulation
   plus a cumulative level selector recompose chapters and score **client-side** (everything is
   embedded), so a single report serves every standard.

### Engines & transports

| Target | Transport | Engine |
|---|---|---|
| `local` | `local://` | native (audits the current host) |
| `user@host` | `ssh://` | native recommended (honors your `~/.ssh/config`), docker possible |
| `<container>` | `docker://` | native (shell-out) or container |

Native-first because a container cannot audit its host, and for an SSH target the native binary uses
your real ssh config / routing / user — exactly like oscap or lynis. The container is a zero-install
fallback for `docker://` targets.

## The source-of-truth pipeline

Controls are authored once and generated outward — never hand-edited as `.rb`:

```
docs/reference/rules.yml ──gen──▶ docs/reference/pavois-content/<os>.yml ──render──▶ profiles/linux/<os>/controls/*.rb
                                                                                          │
                                                                                          └─embed─▶ the binary
```

`rules.yml` holds one entry per control id (shared fields once, `@os`-keyed values only where they
differ). `tools/gen.py` renders the 8 per-OS files; `tools/render.sh` renders the InSpec corpus; the
binary embeds the corpus. The `.rb` corpus and the OSCAL bundle are **derived artifacts** — git-ignored
and rebuilt with `mise run regen`.

## The multi-standard model

One control = one **standard-neutral id** (`domain-object` slug) + **N standard mappings as tags**
(`tag cis:` / `bp28:` / `nist:` / `pci-dss:` / `stig:`) + a `tag domain:` for neutral chaptering. The
**level** is set per standard (`tag level_cis: 1|2`, `tag level_bp28: minimal..high`). A standard is a
*view*, never a duplicated control set — so a single scan answers "am I CIS L1?" and "am I ANSSI
minimal?" at once.

## Scoring & the qualified verdict

- **A–E grade** with critical-failure caps (the formula is published and frozen by a unit test).
- **Qualified verdict** per control: an *evidence type* (effective-runtime, persistent-config,
  inventory-state, filesystem-state, …) and a *reboot-survivability* axis.
- **Runtime-only cap.** A PASS that proves the live state but not its persistence is *runtime-qualified*
  and caps the grade under A until persistence is proven (`harden apply --reboot --scan` re-scans after
  a real reboot to earn a reboot-proven PASS).

## OSCAL export

`pavois oscal` publishes the baseline as OSCAL (catalog + per-OS profiles). Document UUIDs are derived
deterministically (SHA-256 name-based). Assessment-results (a scan as OSCAL) is on the roadmap.

## The site (`site/`)

A static, bilingual (FR/EN) Astro site — the public reference. It reads the same enriched content the
binary is built from and renders the rule fiches, the standards views, the glossary and the handbook.
It ships zero bundled runtime JS in production; code blocks are highlighted at build time (Shiki) and
the large rule/standards tables are windowed client-side for performance.

## Offline tooling (`tools/`, Python)

Not the product — the binary is 100% Go. Python covers generation (`gen.py`), reference rendering,
cross-validation against authoritative sources (`validate_*.py`), and the **norm-studio** MCP server
that surfaces official sources. It runs via `uv` with pinned deps.

## CI exit codes

The CINC exit code (`0` pass / `100` failures / `101` error) is preserved so a pipeline can gate on it
(`--fail-under` sets the threshold). See [Run Pavois in CI](https://pavois.dev/en/handbook/ci-integration/).
