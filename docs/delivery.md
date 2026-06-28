# pavois delivery tracker

End-to-end hardening delivery, **one OS at a time**. An OS is **delivered** only when
every applicable gap has a remediation (Chef-native, no bash) and it is documented.

Stages per OS: **detect → scan → curate** (drop cross-OS noise) **→ remediation**
(Chef resources / declarative template drop-ins) **→ re-scan** (grade rises) **→
document → delivered**.

## Status by OS
| OS | detect | scan | curate | remediation ready | delivered |
|----|:--:|:--:|:--:|----|:--:|
| **debian12** | ✓ | ✓ grade E · 353 gaps | ✓ −9 SELinux | 102 / 353 Chef-native | ☐ |
| debian13 | ✓ | ☐ | ✓ −9 SELinux | ☐ | ☐ |
| ubuntu2404 | ✓ | ☐ | ✓ already clean | ☐ | ☐ |
| ubuntu2204 | ☐ | ☐ | ✓ already clean | ☐ | ☐ |
| rhel9 | ☐ | ☐ | ☐ (drop AppArmor/ufw) | ☐ | ☐ |
| rhel8 | ☐ | ☐ | ☐ | ☐ | ☐ |
| almalinux9 | ☐ | ☐ | ☐ | ☐ | ☐ |
| fedora | ☐ | ☐ | ☐ | ☐ | ☐ |

Test fleet (Incus): `pavois-debian` 10.76.154.119 (RUNNING) · `pavois-rocky9` (stopped).

## Remediation readiness — Chef NATIVE resources, no bash (no compromise)

### Ready now — derived from the reference check → native resource
| Resource | Domains | debian12 gaps |
|----------|---------|:--:|
| `sysctl` | Kernel & network | 44 |
| `package` | Packages | 22 |
| `file` | File ownership / permissions | 12 |
| `kernel_module` | Kernel modules | 12 |
| `service` | systemd services | 12 |
| **subtotal** | | **102** |

### Pending — declarative `template` / `file` drop-in (content sourced once from NixOS)
| Domain | debian12 gaps | Chef approach (no bash) |
|--------|:--:|------|
| Audit (auditd) | 63 | `template` audit.rules / auditd.conf |
| Mounts | 33 | `mount` resource (native — to wire, will move to Ready) |
| Kernel build (kconfig) | 25 | mostly compile-time → assess applicability |
| File permissions | 13 | `file` (extend check parser → Ready) |
| SSH | 13 | `template` /etc/ssh/sshd_config.d/ + `notifies` reload |
| Passwords (pwquality) | 12 | `template` pwquality.conf |
| Firewall | 11 | `ufw` / `nftables` resource or `template` |
| Accounts (PAM modules) | 9 | `template` pam.d |
| Kernel command line | 8 | `template` grub drop-in + grub resource |
| other | ~64 | per-domain template / native resource |

## Remediation engine (Go `pavois harden`) — built & proven
- [x] `harden plan <target>`: scan + reference → state-aware plan (compliant never
      re-applied; gaps opt-in; deduped batched `baseline_packages`). Reads remediation
      from the reference (knowledge is data, not code).
- [x] `harden apply <plan>`: compiles enabled items into **native Chef resources, no
      bash** (batched `package`, `sysctl`, `service`, `file`, kernel-module via
      modprobe.d). Installs cinc-client (omnitruck), converges via `cinc-apply`.
- [x] **Safety**: sshd → one `file` drop-in with `verify 'sshd -t -f %{path}'` (no
      lockout) + `notifies :reload` (keeps sessions); `reboot_required` flag warned,
      never auto-rebooted; enabled-but-pending rules warn (no silent skip).
- [x] **Proven live on debian12**: baseline at/auditd/chrony/cron (1 apt txn) +
      sysctl kernel.panic_on_oops + **PermitRootLogin no** (verified, reloaded, stayed
      connected). Re-scan moved passing 269→289, n/a 81→45.
- [x] Curation: cross-OS prune (SELinux/grub2/secure/landscape) + threshold collapse
      (faillock/pwquality value-per-norm splits → one strictest, all-norms control).

## Validation features (prove a remediation is real, not self-graded)
- [x] `harden apply --scan`: re-scans after converge and reports, per applied control,
      whether it now PASSES (flags broken remediations).
- [x] `pavois diff <before.json> <after.json>`: fixed / regressed / (de)activated controls
      + grade delta between two scans.
- [x] `pavois verify <target>`: **behavioral** validation — attempts the forbidden action
      and confirms the protection holds (root SSH refused, insecure clients absent, ASLR
      really randomizes…). Tool-independent, drop-in aware. Probes in
      docs/reference/behavioral-probes.yml (extensible). Proven on debian12: 2/3 hold,
      tftp client surfaced as a real gap.

## Next steps
- [x] Terraform-style `apply`: shows the real `cinc-apply --why-run` diff, then prompts
      `[y/N]` before converging (`--yes` for CI). Proven on debian12.
- [ ] Finish the triad: rename `plan`→`template`, add a standalone `plan` (why-run diff
      + predicted compliance delta), and have `apply` re-scan + show the new grade.
- [ ] Compiler conflict-detection (same target, different value → error) for the
      remaining exact-value cases (umask).
- [ ] Fill pending remediations (audit rules, pwquality, pam…) — derive from the check
      / source content once from NixOS, pavois-owned.
- [ ] Wire the `mount` resource + extend `file` parsing → grows the Ready set.
- [ ] Symmetric curation for the rpm family (drop AppArmor/ufw-exclusive controls).
