# Brief, pavois adopts scankit v0.2.0 (opposable assessment + OSCAL)

**Status:** DONE. Additive, non-breaking. No rule, ingestion or golden-baseline change.

## Outcome

Implemented as specified:

- `go.mod` bumped to `github.com/stephrobert/scankit v0.2.1` (online, no `replace`).
- `go/internal/audit/assessment.go`: the `audit → assessment` mapper (typed status incl.
  `not-evaluated`, effective evidence observed/expected/source, the `proves` triple, exact
  references, waiver).
- `go/cmd/provenance.go`: the `Run` envelope (binary + **ruleset content** digests, target,
  timestamp, scope).
- `go/cmd/scan.go`: `pavois scan --format oscal` (OSCAL assessment-results) and the `run`
  provenance block in `--format json`.
- `go/cmd/bundle.go`: `ruleset_sha256` (ruleset content digest) in `manifest.json`.

**OSCAL conformance is verified, not asserted.** The emitted assessment-results validates clean
against the official NIST OSCAL 1.1.2 schema (`oscal-cli assessment-results validate`, or
`check-jsonschema --schemafile oscal_assessment-results_schema.json`). Validating surfaced a
missing required `description` on `result`/`finding` in scankit's own `report.OSCAL`, fixed
upstream and released as **scankit v0.2.1** (a regression test guards it). Non-regression:
replaying a pre-change scan re-grades identically (byte-stable evaluation path); a real debian12
scan passes end-to-end.

---

**Original brief below (proposal / handoff).** Additive, non-breaking. Reuses machinery pavois
already has.

## Why

scankit **v0.2.0** adds a shared, auditor-facing model:

- `assessment.Result`: typed `Status` (`pass|fail|not-applicable|not-evaluated|error`),
  `Evidence` (observed vs expected + `Source` + `Type` + `Proves` triple), exact `Reference`s
  (framework + id + version), `Remediation`, `Waiver`.
- `assessment.Run`: provenance envelope: `Tool`/`Ruleset` (name + version + **digest**),
  `Target`, `Timestamp`, `Source`, `Scope`.
- `report.OSCAL(w, assessment.Assessment)`: deterministic **OSCAL 1.1.2 assessment-results**
  (reviewed-controls + observations + findings).

pavois already has a rich product-side layer (`go/internal/audit/audit.go`,
`go/internal/render/`, `go/cmd/oscal.go`, `go/cmd/bundle.go`). The three opposability gaps
identified, **(a)** no OSCAL *assessment-results* (only catalog/profile = the standard, never
the run outcome), **(b)** no typed per-control result carrying observed/expected/source, and
**(c)** no run provenance in the scan JSON: are exactly what scankit v0.2.0 now covers. pavois
keeps its internal `audit.Result`; it *also* serializes to `assessment.*` for exchange.

## Mapping `audit` → `assessment` (one new file, e.g. `go/internal/audit/assessment.go`)

Per control in `audit.Evaluate`'s classification loop, build one `assessment.Result`:

| assessment field | pavois source |
|---|---|
| `Control` | `Control.ID` |
| `Title` | `Control.Title` |
| `Status` | map `status(c)`: `passed`→`Pass`, `failed`→`Fail`, `skipped` **with** `WaiverData.Justification`→`Fail`+`Waiver`, `skipped` via `only_if` guard→`NotApplicable`, control not in this standard/level run→`NotEvaluated` |
| `Severity` | `severity(Control.Impact)` |
| `Subject` | the InSpec result target (resource/host) |
| `Evidence.Observed` | the failing `Results[].Message` / `CodeDesc` |
| `Evidence.Source` | the `check` YAML (`describe command('sshd -T')…`) → `"command:sshd -T"` |
| `Evidence.Type` | the `evidence`/`evidence_type` tag |
| `Evidence.Proves` | **already computed**: `audit.Proves(evidence)` returns the `[running, persistent, reboot-survivable]` triple |
| `References` | the `norms` tags (`cis`, `stig`, `bp28`→`anssi-bp028`, `nist`, `pci-dss`) → `[]Reference{Framework, ID, Version}` |
| `Remediation` | `Control.Desc` (remediation prose) |
| `Waiver` | `WaiverData.Justification` |

The `not-evaluated` status is the key new signal: emit a `Result` for every control in the
selected standard/level that produced no InSpec result, so a gap can never read as a pass.

## `assessment.Run` from what pavois already stamps

- `Tool` = `{Name:"pavois", Version:<build version>, Digest:<pavois_binary_sha256>}`: the
  binary digest already exists in `bundle.go`'s manifest.
- `Ruleset` = `{Name:"pavois-baseline", Version:<ruleset_version>, Digest:<content hash>}`: version exists; **add a content digest of the evaluated profile** (closes gap: the bundle
  manifest has a version string but no content hash).
- `Target` = `{Platform:Report.Platform.Name+Release, ID/Region:<scan flags>}`.
- `Timestamp` = `render.Meta.Timestamp` (RFC3339 UTC).
- `Source` = transport (`ssh`/`local`/`docker`) → `"live"`; export mode → `"export"`.
- `Scope` = the standard(s)/level(s) evaluated + what was filtered out.

## Wiring

1. **New output**: `report.OSCAL(out, asmt)`, either a `pavois scan --format oscal`, or a
   `pavois oscal-results` command that writes `assessment-results.json` next to the existing
   `pavois-catalog.json` / `profiles/`. This is the single biggest opposability win.
2. **Provenance in the scan JSON**: the current `--format json` (ad-hoc `map[string]any` in
   `go/cmd/scan.go`) has no host/OS/timestamp/tool-version/ruleset-digest: embed the `Run`.
3. **Bundle**: add the ruleset content digest to `bundle.go`'s `manifest.json`.

## Out of scope (stays pavois-specific)

A-E grade formula and bands, the qualified verdict (keep using `Proves`), `RemediationClass`
taxonomy / remediable-grade, the InSpec/CINC ingestion shape, the HTML renderer, and the
baseline identity (`baseline.yml`, `pavois.dev` namespace). `assessment.*` is the shared
serialization the family (pavois, pepin, pitstop) all emit, not a replacement for pavois's
internal model.

## Effort

Small and isolated: one mapper, one output path, provenance threaded into the JSON envelope,
one digest added to the bundle. No change to rules, InSpec ingestion, scoring or the frozen
debian12 golden baseline. Bump `go/go.mod` to `github.com/stephrobert/scankit v0.2.0` (drop the
`replace` when ready) to pick up the `assessment` package and `report.OSCAL`.
