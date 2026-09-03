package audit

import (
	"encoding/json"
	"testing"
)

// The InSpec JSON report is EXTERNAL INPUT: it is produced by cinc-auditor, a separate program,
// possibly running on a machine we do not control (an SSH target, a container). pavois must not
// panic on a malformed, truncated or hostile report, and the grade it derives must stay inside its
// published bounds whatever the report says. These fuzz targets assert exactly that, so a crash or
// an out-of-range grade is a test failure rather than a stack trace in front of an operator.

// FuzzEvaluate drives the whole report pipeline (Evaluate -> GradeResult -> Breakdown -> Headline)
// on arbitrary JSON. Invariants: no panic, points always within 0..100, and the letter always one
// of the five published bands. A grade outside those bounds would silently break `--fail-under`,
// which is the CI gate people trust.
func FuzzEvaluate(f *testing.F) {
	f.Add([]byte(`{}`))
	f.Add([]byte(`{"profiles":[]}`))
	f.Add([]byte(`{"platform":{"name":"debian","release":"12"},"profiles":[{"title":"t","controls":[]}]}`))
	f.Add([]byte(`{"profiles":[{"controls":[{"id":"ssh-x","impact":1.0,"tags":{"cis":"5.1.20","level_cis":"1"},` +
		`"results":[{"status":"failed"}]}]}]}`))
	f.Add([]byte(`{"profiles":[{"controls":[{"id":"a","impact":0.5,"tags":{"bp28":"R33","level_bp28":"minimal"},` +
		`"results":[{"status":"passed"}]},{"id":"b","impact":-3,"tags":null,"results":[]}]}]}`))
	f.Add([]byte(`{"profiles":[{"controls":[{"id":"w","impact":0.95,"waiver_data":{"justification":"x","run":false},` +
		`"results":[{"status":"skipped","skip_message":"waived"}]}]}]}`))

	standards := []string{"", "cis", "bp28", "nist", "pci-dss", "stig", "bogus"}
	levels := []string{"", "1", "2", "minimal", "high", "bogus"}

	f.Fuzz(func(t *testing.T, data []byte) {
		var r Report
		if err := json.Unmarshal(data, &r); err != nil {
			return // not a report; the CLI reports this as an error, it is not a crash
		}
		for _, std := range standards {
			for _, lvl := range levels {
				res := Evaluate(&r, "fuzz", std, lvl)

				letter, points, _ := GradeResult(res)
				if points < 0 || points > 100 {
					t.Fatalf("points out of bounds: %d (standard=%q level=%q)", points, std, lvl)
				}
				switch letter {
				case "A", "B", "C", "D", "E":
				default:
					t.Fatalf("grade letter %q is not a published band (standard=%q level=%q)", letter, std, lvl)
				}
				// A critical failure must never leave the E band: it is the rule the whole
				// scoring page rests on, so prove it holds for any report shape.
				if res.Summary.Counts["critical"] > 0 && points > 30 {
					t.Fatalf("critical failure did not cap the score: points=%d", points)
				}
				_ = Breakdown(&r, std, lvl)
				_ = Headline(res)
			}
		}
	})
}

// FuzzProves fuzzes the evidence-type classifiers that decide what a PASS is allowed to claim.
// They take a free-form tag straight out of the report's `tags`, so they must never panic and
// Proves must always return three non-empty, human-readable strings.
func FuzzProves(f *testing.F) {
	for _, s := range []string{
		"", "effective-runtime", "persistent-config", "inventory-state",
		"filesystem-state", "manual", "behavioral", "unknown-type", "EFFECTIVE-RUNTIME",
	} {
		f.Add(s)
	}
	f.Fuzz(func(t *testing.T, evidence string) {
		got := Proves(evidence)
		for i, s := range got {
			if s == "" {
				t.Fatalf("Proves(%q)[%d] is empty; every evidence type must state what a pass proves", evidence, i)
			}
		}
		_ = FullPass(evidence)
	})
}
