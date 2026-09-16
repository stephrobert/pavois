# Releasing Pavois

A release is a claim about real machines. This page is the order in which that claim is made
checkable, and the traps that are easy to walk into.

## The one ordering constraint

**The repository must be public before the tag is pushed.**

Five steps of `.github/workflows/release.yml` are gated on `!github.event.repository.private`: the
SLSA build-provenance attestation, the SBOM attestation, the Cosign install, the keyless signature
of `checksums.txt` and the copy of the provenance bundle. GitHub refuses attestations on a
user-owned private repository, and a Cosign signature is written to the public Rekor transparency
log, which should not happen while a repository is private. Both gates are correct.

What is not obvious is what happens when they hold: a gated step **skips**. It does not fail. So a
tag pushed while the repository is private produces a perfectly green release with no provenance, no
SBOM attestation and no signature, and nothing anywhere says so. The release looks identical to a
real one and is worth much less.

The `guard` job refuses to start the pipeline in that case, and the preflight below refuses before
the tag exists at all. Neither is a substitute for knowing the order.

## The sequence

```bash
mise run release:preflight v0.1.0   # refuses, and says why
# make the repository public
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0              # this is what publishes
```

`mise run release:preflight vX.Y.Z` reports every verdict rather than stopping at the first, so one
run tells you everything that is left. It checks the tag shape and availability, the working tree
and branch, that the repository is public, that the corpus renders and lints, the project's own
gates (`prepush`, `oscal:verify`, `secrets:history`), the field evidence, what the site says, the
CHANGELOG, and CI on the exact commit.

## The two checks CI cannot make

**The corpus the binary embeds.** `profiles/linux/*/controls/` is derived from
`docs/reference/rules.yml` and is gitignored. The release workflow renders it and the build embeds
it with `go:embed`. A stale corpus therefore does not fail a build, it ships. `gen:verify` and
`lint:shell-first-word` are release gates for that reason, not just contributor conveniences.

**The evidence behind the support claim.** `mise run release:evidence debian12 debian13` finds the
most recent golden-path campaign for each system, checks it reached `GOLDEN PATH: PASSED`, and then
compares the ruleset content digest the campaign's final scan recorded against the digest of the
corpus being released.

That last comparison exists because of a real mistake. A Debian 12 campaign finished at 13:10 and
reported a clean two-pass convergence. At 13:40 a defect was fixed where a control's command lost
its root privileges, so ninety-six controls had been returning verdicts they never measured. Four of
them were in that campaign's "did not converge" list, and were read as a Debian 12 remediation gap.
They were nothing of the sort: their commands had simply never run as root. The campaign log said
`PASSED` and was useless, and nothing in it said so. The digest comparison is what says so.

## Tag shape

Only `vX.Y.Z`, with an optional `-rc.N`, `-beta.N` or `-alpha.N`, publishes a release. The workflow
trigger is `tags: v*`, which is as wide as it looks: this repository already carries a
`v0.9.0-clean-room` lab tag that matches it. The `guard` job rejects anything that is not a release
version before a single binary is built.

## Two versions, not one

The tool version is what a tag names. The **baseline** version lives in
`docs/reference/baseline.yml` and moves on its own rules: MAJOR when controls are removed or ids
renamed, MINOR when controls or mappings are added, PATCH for fixes that do not change coverage.

They are deliberately separate. A fix to the scanner is not a change to the standard it evaluates.
Every report cites the baseline version and its content digest, so an archived result stays
interpretable long after the tool has moved on. Both are tracked in `CHANGELOG.md`.

## What the release publishes

Static binaries for linux and darwin on amd64 and arm64, `.deb` and `.rpm` packages, a
`checksums.txt` covering all of them, a CycloneDX SBOM, a SLSA build-provenance attestation and a
keyless Cosign signature of the checksums. `.github/workflows/verify.yml` is the consumer side of
that: run it after the assets exist and it proves, with no special access, that a third party can
check what was published.

## After the tag

Watch the run, then verify the result the way a stranger would:

```bash
gh run watch --repo stephrobert/pavois
gh workflow run verify.yml --repo stephrobert/pavois -f tag=v0.1.0
```

A release nobody has verified from the outside is a release whose verification recipe is a comment.
