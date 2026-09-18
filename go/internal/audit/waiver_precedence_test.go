package audit

import "testing"

// A control may declare BOTH an applicability condition and a waiver, and `mount-var-noexec` does.
// The two say different, compatible things:
//
//	applies_if  CIS words the requirement "IF a separate partition exists for /var"
//	waiver      where it DOES apply, the risk is accepted: noexec on /var leaves apt and dnf
//	            unable to run maintainer scripts, so the machine cannot be patched
//
// Dropping either one loses a fact, so tools/lint_applies_if.py allows the pair on purpose. What
// must never be ambiguous is the RUNTIME: a waiver wins, because a waiver is the statement an
// auditor can refuse, and a not-applicable is one they cannot argue with. Reporting that control
// as n/a would hide an accepted risk behind a fact about the filesystem.
//
// This test is the whole enforcement of that rule. It is not in the linter because the linter
// reads declarations and this is about what the report says.
func TestAWaiverWinsOverADeclaredNonApplicability(t *testing.T) {
	// Exactly what cinc emits for a control carrying both: the waiver suppresses the run, so the
	// skip message is the waiver's, and waiver_data carries the justification.
	const both = `[
	  {"id":"mount-var-noexec","impact":0.5,
	   "waiver_data":{"justification":"noexec on /var breaks apt/dnf: accepted risk"},
	   "results":[{"status":"skipped","skip_message":"Skipped control due to waiver condition: noexec on /var breaks apt/dnf: accepted risk"}]}
	]`
	// The same control on a host where the guard is what fired instead.
	const naOnly = `[
	  {"id":"mount-var-noexec","impact":0.5,
	   "results":[{"status":"skipped","skip_message":"Skipped control due to only_if condition: n/a: requires /var mounted"}]}
	]`

	res := Evaluate(repOf(t, both), "host", "", "")
	if res.Waived != 1 {
		t.Errorf("a control carrying both was not counted as waived: waived=%d", res.Waived)
	}
	if res.NotApplicable != 0 {
		t.Errorf("a waived control was ALSO counted as not applicable: na=%d", res.NotApplicable)
	}

	// And the other way, so this does not pass by counting everything as waived.
	res = Evaluate(repOf(t, naOnly), "host", "", "")
	if res.NotApplicable != 1 || res.Waived != 0 {
		t.Errorf("a declared non-applicability with no waiver: na=%d waived=%d, want 1 and 0",
			res.NotApplicable, res.Waived)
	}
}
