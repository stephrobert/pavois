# Changelog: pavois Effective-Configuration Hardening Baseline

All notable changes to the **published baseline** (the standard `pavois oscal` emits, identity in
`docs/reference/baseline.yml`) are recorded here. The baseline is versioned independently of the
pavois tool. Format follows [Keep a Changelog](https://keepachangelog.com); versioning is semantic
(MAJOR = controls removed / ids renamed, MINOR = controls or mappings added, PATCH = fixes).

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
