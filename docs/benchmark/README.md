# Pavois vs OpenSCAP / Lynis — reproducible benchmark

Evidence for the comparison on [the tools page](https://pavois.dev/en/docs/tools/). Everything
here is reproducible from a fresh Debian 12 VM; nothing is hand-asserted.

## Method

A fresh Debian 12 VM is provisioned, the scanners + CINC are installed once, a clean baseline
snapshot is taken, and **every run restores that identical snapshot first** (so the starting
state never drifts). The scripts:

- `tools/benchmark/effective-config-bench.sh <user@host> <key> <ssg-debian12-ds.xml>` — sets up
  the scenario and runs all three scanners, emitting `reports/benchmark-dropin.md`.
- `test-vms/bench.sh` — the lab wrapper (provision → snapshot → restore → run). Not published
  (it references the local Incus lab).

## Versions (this run)

| Component | Version |
|---|---|
| Pavois | CINC Auditor 7.1.7 |
| OpenSCAP | oscap 1.3.7 |
| SCAP Security Guide | `ssg-debian12-ds.xml` (0.1.x) |
| Lynis | 3.0.8 |
| Target | Debian 12, fresh Incus VM |

## Scenario 1 — sshd drop-in overrides PermitRootLogin

Main `/etc/ssh/sshd_config` says `PermitRootLogin no`; a drop-in in `/etc/ssh/sshd_config.d/`
says `yes` (the value `sshd -T` resolves). Exact checks:

```bash
# what a file probe reads vs the effective value
grep -iE '^\s*PermitRootLogin' /etc/ssh/sshd_config        # -> PermitRootLogin no
sudo sshd -T | grep -i '^permitrootlogin'                   # -> permitrootlogin yes

# the three scanners on the same host
pavois scan user@host --key KEY --sudo --on-target --format json   # ssh-disable-root-login -> FAIL
sudo oscap xccdf eval --rule xccdf_org.ssgproject.content_rule_sshd_disable_root_login ssg-debian12-ds.xml  # -> pass
sudo lynis audit system --quick --quiet                     # SSH-7408 suggestion (caught, heuristic)
```

| Scanner | Reads | Result |
|---|---|---|
| Pavois | `sshd -T` | **FAIL** (caught), mapped `ssh-disable-root-login` |
| OpenSCAP 1.3.7 + SSG | OVAL on the file | **PASS** (false negative) |
| Lynis 3.0.8 | `sshd -T` | warns (SSH-7408), caught but heuristic, unmapped |

## Coverage gap (auditable)

`tools/coverage_gap.py` maps Pavois controls to SSG rules (via `ssg:` tags) and triages with
oscap's own verdicts on the real target. Full data: **[`coverage-gap-debian12.csv`](coverage-gap-debian12.csv)**
(315 SSG rules Pavois does not map, with each rule's oscap verdict).

- raw gap: **315** SSG rules
- triaged: **87 applicable & failing** (the real backlog), 74 applicable & already passing,
  **139 notapplicable** on Debian (e.g. SELinux), 15 not auto-checked
- symmetric: Pavois applies to **523 of its 607** Debian 12 controls on a fresh host (84 N/A)

Reproduce:

```bash
oscap xccdf eval --results gap-res.xml ssg-debian12-ds.xml   # on the target, for applicability
python3 tools/coverage_gap.py --os debian12 \
  --datastream ssg-debian12-ds.xml --oscap-results gap-res.xml --format json
```

## Honesty notes

- Lynis resolves the SSH drop-in too (it runs `sshd -T`); its limit is being heuristic /
  non-normative, not this blind spot.
- Raw rule counts (Pavois 607, SSG 887) overstate on both sides; the applicable, comparable
  sets are what matter.
- The gap's high-severity entries are mostly arbitration cases on Debian (SELinux = N/A under
  AppArmor; ntp/timesyncd are alternatives to chrony), not clear missing controls.
