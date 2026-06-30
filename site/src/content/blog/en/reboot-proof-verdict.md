---
lang: en
title: "Reboot-proof compliance: what a Linux PASS really proves"
description: "A green check is not binary. Pavois now scores whether a PASS survives a reboot, so a clean A only goes to a host that is hardened and reboot-proof, not just live."
datePublished: "2026-06-28"
dateModified: "2026-06-28"
category: methodology
tags: ["compliance", "hardening", "sysctl", "auditd", "CINC"]
keywords: ["reboot-proof", "effective configuration", "runtime vs persistence", "Linux hardening", "compliance score"]
featured: true
---

A passing control should tell you two things, not one: that the setting is **active now**, and that it **survives a reboot**. Most scanners only prove the first. Pavois now proves both, and its A to E grade reflects the gap. A runtime-only PASS (a live `sysctl` value that is not pinned on disk) no longer earns a clean **A**: the grade is capped and flagged **runtime-qualified** until persistence is proven. This post explains why that distinction matters and how Pavois measures it.

## The trap: runtime is not persistence

`sysctl net.ipv4.conf.all.rp_filter` can return `1` right now because someone ran `sysctl -w` after boot. Nothing in `/etc/sysctl.d` pins it. The control passes today and **regresses on the next reboot**. A scanner that reports a flat pass hides that risk behind a green check. The honest answer is: running yes, reboot-survivable unknown.

Pavois splits the verdict into two independent axes. **Evidence type** says what the check reads (the resolved running state, a persistent config file, package inventory, filesystem metadata). **Reboot-survivability** says whether a PASS proves a durable state. They are independent: a kernel's compiled `kconfig` is a runtime read that is reboot-proof, while a live mount option may not be.

## How Pavois proves persistence

Wherever there is a clean source of truth, the check asserts both the live value and its persistent backing:

- **sysctl** verifies the live value with `kernel_parameter` **and** that it is pinned in a file under `/etc/sysctl.d`.
- **mount options** verify the active option **and** an entry in `/etc/fstab` or a systemd `.mount` unit.
- **kernel command line** verifies `/proc/cmdline` **and** the parameter in the bootloader config.
- **audit rules** verify the rule is loaded with `auditctl -l` **and** present in `/etc/audit/rules.d`.

Verify it yourself on a target:

```bash
pavois harden plan user@host --sudo
# flip a few controls to apply: true, then converge and re-scan
pavois harden apply hardening-plan.yml --reboot --scan
```

With `--reboot`, Pavois converges the fixes, reboots the host, waits for it to return, and re-scans. A control that passes in that report is **reboot-proven**: it survived a real boot, not just a live write.

## Key takeaways

- A PASS now states **running now** versus **reboot-survivable**, on the fiche, in the report, in the JSON export and the OSCAL catalog.
- A grade only reaches a clean **A** when the passing controls prove persistence, not just live state.
- `pavois harden apply --reboot --scan` turns that claim into an empirical, reboot-proven result.

## Next steps

- Read the method: [the qualified verdict](/en/handbook/qualified-verdict/) and [how the grade is computed](/en/handbook/scoring-methodology/).
- Browse the controls and their evidence type in the [control explorer](/en/rules/).
- Go deeper on Linux hardening with the author's guides on [blog.stephane-robert.info](https://blog.stephane-robert.info/docs/securiser/).
