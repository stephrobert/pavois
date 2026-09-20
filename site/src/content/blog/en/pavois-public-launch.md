---
lang: en
title: "From first public release to an evidence-backed delivery chain"
description: "Pavois has been public since 16 September 2026. The first releases exposed a gap between tests run from a checkout and the standalone artefact delivered to a clean machine. Here is what that gap changed in the delivery chain, and what is now mechanically verified."
datePublished: "2026-09-18"
dateModified: "2026-09-18"
category: project
tags: ["pavois", "compliance", "hardening", "open source", "CINC"]
keywords: ["Linux compliance scanner", "effective configuration", "OpenSCAP alternative", "Linux hardening", "open source launch"]
featured: true
---

On 16 September 2026, Pavois went from a private repository to a public project. It is a **Linux compliance scanner** that audits a machine's **effective** configuration rather than its configuration files, grades it A to E per standard (ANSSI BP-028, CIS, PCI DSS, NIST, STIG), and can apply and then **undo** its own hardening. This post covers why it stayed private for so long, what the first 48 hours broke, and where I want to take it.

## Why it stayed private

The code was ready well before. What was not ready was me. I pushed the date back more times than I counted, for one reason: fear of looking ridiculous. Publishing a compliance tool means exposing yourself to someone running it on their machine and finding out the verdict is wrong. In this field, **a tool that is wrong is worse than useless**: it delivers false confidence, and false confidence on a production server has a real cost.

That reasoning has a flaw, and it cost me months: a tool that stays private never gets it wrong in public, but it never gets better either. No amount of tests written by the person who wrote the code replaces one user who does not know what they are supposed to do.

## What the first 48 hours proved

Five releases in three days. That is not product instability: it is a delivery chain being hardened in public, and the cadence measures how fast the fixes landed, not how fast things broke. What was actually wrong fits in one sentence.

**v0.1.0 and v0.1.1 shipped a binary incapable of doing its job.** Both times for the same reason: every test I ran lived **inside the repository**, where the rule profiles and the reference sit on disk. The published binary arrives alone on a fresh machine. Both times a user on a clean VM found it, not me. v0.1.2 did worse in another register: three empty embedded directories, which is **not a build error**. It compiles, it publishes, and the only symptom is a sentence the user meets on their first command: `this binary embeds none and none is on disk`.

The fix was not a patch, it was a ladder where each rung catches a class the previous one cannot see:

| rung | what it catches |
|---|---|
| `prepush` | everything a pull request would refuse, offline |
| `release:standalone` | a path resolved against the current directory |
| `release:ci-build` | what the **release** builds, not what I build |
| `release:preflight` | the package, extracted and executed |
| `release:scenario` | the whole scenario on a **clean VM** |
| `release:published` | the artefact GitHub **actually** published |

The scenario rung carries **one assertion per closed first-contact issue**. An issue closed only in a changelog comes back; an issue closed with a line in a harness does not.

In three days, strangers found what months of anxiety had not fixed. That is the strongest argument I know against keeping a project private.

## What Pavois does, in one idea

**It audits resolved state, not files.** A scanner reading `/etc/ssh/sshd_config` misses `Include` directives, drop-ins, and everything a distribution package layers on top. Pavois asks the daemon what it actually applies:

```bash
# what most scanners do
grep PermitRootLogin /etc/ssh/sshd_config

# what Pavois does
sshd -T | grep permitrootlogin
```

Same principle throughout: `sysctl -a` for the kernel, `systemctl show` for units, `nginx -T` and `apachectl -S` for web servers. It costs more (it needs root, hence `--sudo`) and it is the only reading that describes the machine as it runs.

```bash
pavois scan local --sudo          # A to E grade + a self-contained HTML report
pavois harden plan user@host --sudo --key ~/.ssh/id_ed25519
pavois harden apply plan.yml --reboot --scan   # a PASS after reboot is proven
```

## Where I want to take it

The goal is not to pile up controls. It is to make Pavois a **methodology you can argue with**: a tool whose verdicts can be challenged because they are motivated, sourced and reproducible.

**A qualified verdict rather than a green light.** A PASS has to say two things: the setting is live now, and it survives a reboot. Those are two independent axes, and the grade accounts for both. It is already in place and [explained here](/en/handbook/qualified-verdict/).

**Three states, not two.** ALLOWED, BLOCKED and **UNKNOWN**. Absence of evidence is never evidence of absence. A control Pavois cannot measure has to say it cannot measure it, and that verdict must not count as a pass. `UNKNOWN` beats false confidence, and that is the work in progress.

**Say what it cannot fix.** A separate filesystem is decided at install time, a missing KSPP option needs a rebuilt kernel, a GRUB password can lock you out. Those three classes are not something an `apply` can close, so the report prints **two grades**: the raw grade, and the remediable posture, meaning what Pavois can reach on its own.

**Know how to go back.** Among the tools that remediate (OpenSCAP, Ubuntu's USG, the CIS Build Kits, ansible-lockdown), none ships the inverse of its own remediation. Pavois does, at 96% measured on a fresh Debian 12, and it **publishes the 4% that do not come back**, one by one. A rollback is not a null operation, and the manifest says so before you confirm.

**Output other tools can read.** The rule base exports as OSCAL, results as SARIF, JUnit, JSON and CSV. Evidence that cannot leave its own tool is not evidence, it is a screenshot.

## What is not true today

Pavois covers **nine** Linux systems. **Two** have been through the full campaign on a clean VM: Debian 12 and Debian 13. The other seven are curated and statically validated, but no campaign has run on them: treat them as experimental. "9 systems supported" and "9 systems proven" are not the same sentence, and only one of them is true.

There is no fleet aggregation either. One run audits one target. A loop and a report directory are enough, because every scan emits a complete JSON, but that is a stated gap, not a hidden feature.

## Key takeaways

- Pavois has been public since 16 September 2026, under Apache-2.0.
- It audits **effective** configuration (`sshd -T`, `sysctl`, `systemctl show`), not files.
- The gap that mattered was not in the controls but in the packaging: tests run from a checkout cannot see what a standalone artefact does on a clean machine. Five releases in three days closed that hole, and each rung of the ladder is the trace of it.
- The direction: a qualified verdict, three states including `UNKNOWN`, two grades including the remediable posture, and a rollback that publishes its own limits.

## Next steps

- [Get started](/en/start/): from a verified download to a first verdict.
- [Browse the controls](/en/rules/) and their evidence type.
- [How the grade is computed](/en/handbook/scoring-methodology/).
- Hit a bug, or a machine that reacts badly? `pavois support` prepares the report, without your machine's identity.
- For Linux hardening more broadly, my guides on [blog.stephane-robert.info](https://blog.stephane-robert.info/docs/securiser/).
