package audit

import (
	"strings"

	"github.com/stephrobert/scankit/assessment"
)

// This file is the bridge from pavois's internal audit model to scankit's shared,
// auditor-facing assessment model (scankit v0.2.0). pavois keeps its own audit.Result /
// grade / qualified-verdict policy; it ALSO serializes each control to an assessment.Result
// so the whole dossier — passes, failures, not-applicable, not-evaluated — travels in the
// family's exchange form (OSCAL assessment-results, see report.OSCAL) exactly like pepin and
// pitstop. The mapper is a pure translation: it invents nothing the report does not carry.

// frameworkOf maps a pavois norm tag to the exact framework identifier an auditor cites. The
// internal tag is a short slug; the assessment.Reference.Framework is the standard's real name.
var frameworkOf = map[string]string{
	"bp28":    "anssi-bp028",
	"cis":     "cis",
	"pci-dss": "pci-dss",
	"nist":    "nist-800-53",
	"stig":    "stig",
}

// Assess translates a report into the shared assessment model for the selected (standard,
// level) view: one Result per control, with a typed status, effective evidence and the exact
// normative references. A control filtered out of the view, or one that produced no InSpec
// result, becomes NotEvaluated — so a coverage gap can never be read as a pass. Uses the same
// applicable/inLevel/status classification as Evaluate, so the two never diverge.
func Assess(r *Report, subject, standard, level string) []assessment.Result {
	var out []assessment.Result
	for _, p := range r.Profiles {
		for _, c := range p.Controls {
			res := assessment.Result{
				Control:     c.ID,
				Title:       titleOf(c),
				Severity:    severity(c.Impact),
				Subject:     subject,
				References:  referencesOf(c),
				Remediation: strings.TrimSpace(c.Desc),
				Labels:      labelsOf(c, standard),
				Evidence:    evidenceOf(c),
			}
			switch {
			case !applicable(c, standard) || !inLevel(c, standard, level):
				// Present in the corpus but outside the requested standard/level: honestly
				// not-evaluated in THIS run, never a silent pass.
				res.Status = assessment.NotEvaluated
			default:
				switch status(c) {
				case "passed":
					res.Status = assessment.Pass
				case "failed":
					res.Status = assessment.Fail
					res.Evidence.Observed, res.Evidence.Expected = failEvidence(c)
				case "skipped":
					// A skipped control is either an ACCEPTED RISK (waived, with a written
					// justification) or genuinely N/A (an only_if guard). A waiver still applies —
					// it is a Fail carrying the justification; a guard is NotApplicable.
					if j := strings.TrimSpace(c.WaiverData.Justification); j != "" {
						res.Status = assessment.Fail
						res.Waiver = &assessment.Waiver{Justification: j}
					} else {
						res.Status = assessment.NotApplicable
					}
				default: // "empty": no InSpec result at all
					res.Status = assessment.NotEvaluated
				}
			}
			out = append(out, res)
		}
	}
	return out
}

// Assessment assembles the full opposable dossier: the provenance envelope plus every control
// result for the selected view. The caller stamps the Run (tool/ruleset digests, target,
// timestamp) — see cmd/provenance.go.
func Assessment(r *Report, run assessment.Run, subject, standard, level string) assessment.Assessment {
	return assessment.Assessment{Run: run, Results: Assess(r, subject, standard, level)}
}

func titleOf(c Control) string {
	if t := strings.TrimSpace(c.Title); t != "" {
		return t
	}
	return c.ID
}

// referencesOf turns the control's norm tags into exact, versioned references. One tag can
// carry several ids ("1.1.1, 1.1.2"); each becomes its own reference.
func referencesOf(c Control) []assessment.Reference {
	var refs []assessment.Reference
	for _, k := range normKeys {
		v := tagStr(c, k)
		if v == "" {
			continue
		}
		fw := frameworkOf[k]
		if fw == "" {
			fw = k
		}
		for _, id := range splitRefs(v) {
			refs = append(refs, assessment.Reference{Framework: fw, ID: id})
		}
	}
	return refs
}

// labelsOf carries the pavois-specific dimensions (domain, level, remediation class, SSG id)
// so the shared renderers and OSCAL props keep the traceability the internal model has.
func labelsOf(c Control, standard string) map[string]string {
	labels := map[string]string{}
	if d := tagStr(c, "domain"); d != "" {
		labels["domain"] = d
	}
	if rc := tagStr(c, "remediation_class"); rc != "" {
		labels["remediation_class"] = rc
	}
	if s := tagStr(c, "ssg"); s != "" {
		labels["ssg"] = s
	}
	if standard != "" && standard != "all" {
		if lv := tagStr(c, "level_"+strings.ReplaceAll(standard, "-", "_")); lv != "" {
			labels["level"] = lv
		}
	}
	if len(labels) == 0 {
		return nil
	}
	return labels
}

// evidenceOf fills the evidence type, its source command and the qualified-verdict triple —
// the effective-configuration proof that makes a pavois verdict opposable. Observed/Expected
// are filled only for a failing control (see failEvidence).
func evidenceOf(c Control) assessment.Evidence {
	e := assessment.Evidence{
		Type:   tagStr(c, "evidence"),
		Source: sourceOf(c),
	}
	// Proves: what a PASS establishes, derived from the evidence type, with the reboot tag as
	// the authoritative persistence axis (same override as the OSCAL catalog, single source
	// audit.Proves). A folded runtime check that asserts on-disk state survives a reboot.
	pr := Proves(e.Type)
	switch tagStr(c, "reboot") {
	case "yes":
		pr[1], pr[2] = "yes", "yes"
	case "no":
		if pr[2] != "no" {
			pr[2] = "no"
		}
	}
	e.Proves = pr
	return e
}

// sourceOf extracts the effective-config source from the first InSpec result's code_desc —
// e.g. "Command: `sshd -T` stdout…" → "command:sshd -T". Best-effort: the report carries no
// dedicated source field, so we read the rendered resource description. Falls back to the
// leading resource token (File, Service…) or "" when nothing is parseable.
func sourceOf(c Control) string {
	if len(c.Results) == 0 {
		return ""
	}
	cd := strings.TrimSpace(c.Results[0].CodeDesc)
	if cd == "" {
		return ""
	}
	if strings.HasPrefix(cd, "Command:") {
		if i := strings.IndexByte(cd, '`'); i >= 0 {
			if j := strings.IndexByte(cd[i+1:], '`'); j >= 0 {
				return "command:" + clip(strings.TrimSpace(cd[i+1:i+1+j]), 160)
			}
		}
	}
	fields := strings.Fields(cd)
	if len(fields) >= 2 {
		return strings.ToLower(strings.TrimSuffix(fields[0], ":")) + ":" + fields[1]
	}
	return ""
}

// failEvidence pulls the observed-vs-expected pair from the failing results. InSpec renders a
// comparison as "expected: X\n got: Y"; when that shape is absent we fall back to the joined
// failure messages (same text the terminal finding shows) as the observed value.
func failEvidence(c Control) (observed, expected string) {
	var msgs []string
	for _, r := range c.Results {
		if r.Status != "failed" {
			continue
		}
		m := r.Message
		if m == "" {
			m = r.CodeDesc
		}
		for _, line := range strings.Split(m, "\n") {
			t := strings.TrimSpace(line)
			switch {
			case strings.HasPrefix(t, "expected:"):
				if expected == "" {
					expected = unquote(strings.TrimSpace(strings.TrimPrefix(t, "expected:")))
				}
			case strings.HasPrefix(t, "got:"):
				if observed == "" {
					observed = unquote(strings.TrimSpace(strings.TrimPrefix(t, "got:")))
				}
			}
		}
		if first := strings.TrimSpace(strings.SplitN(strings.TrimSpace(m), "\n", 2)[0]); first != "" {
			msgs = append(msgs, first)
		}
	}
	if observed == "" {
		observed = clip(strings.Join(msgs, " ; "), 240)
	}
	return observed, expected
}

func splitRefs(s string) []string {
	f := strings.FieldsFunc(s, func(r rune) bool { return r == ',' || r == ';' || r == ' ' })
	out := f[:0]
	for _, v := range f {
		if v = strings.TrimSpace(v); v != "" {
			out = append(out, v)
		}
	}
	return out
}

func unquote(s string) string {
	if len(s) >= 2 && (s[0] == '"' || s[0] == '\'') && s[len(s)-1] == s[0] {
		return s[1 : len(s)-1]
	}
	return s
}

func clip(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return strings.TrimSpace(s[:n]) + "…"
}
