# Security Policy

Pavois is a security tool; we hold its own supply chain and disclosure process to
the standard it audits for.

## Scope

In scope: the `pavois` binary and Go code, the rule corpus and its generators, the
release/signing pipeline, and the site. Out of scope: vulnerabilities in CINC Auditor,
the OS under audit, or third-party datastreams (report those upstream); findings that
require an already-compromised host or physical access.

## Reporting a vulnerability

**Do not open a public issue for security problems.**

Report privately through GitHub's **[Private vulnerability reporting](https://github.com/stephrobert/pavois/security/advisories/new)**
(Security → Advisories → *Report a vulnerability*). If that is unavailable, email the
maintainer at **robert.stephane.28@gmail.com** with `SECURITY` in the subject.

Please include:

- affected version (`pavois version`) and platform;
- a description and, where possible, a minimal reproduction;
- the impact you foresee.

## What to expect

- **Acknowledgement** within 5 working days.
- An initial assessment and severity (CVSS) within 10 working days.
- Coordinated disclosure: a fix and an advisory are published together; you are
  credited unless you prefer to remain anonymous.

## Supported versions

Until the first stable release, only the latest `main` and the most recent tagged
release receive security fixes.

## Supply-chain assurances

- Release binaries are built in CI and published with **SHA-256 checksums** and
  **SLSA build-provenance attestation** (verify with `gh attestation verify`).
- Third-party GitHub Actions are **pinned by commit SHA**.
- Dependencies (Go modules + npm) are scanned weekly for known CVEs; a fixable
  HIGH/CRITICAL fails the build.
