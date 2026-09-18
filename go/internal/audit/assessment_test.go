package audit

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/stephrobert/scankit/assessment"
)

// repOf builds a Report from a JSON array of controls (single profile), so the anonymous
// Results/WaiverData fields are populated exactly as cinc emits them. A "~" in the JSON stands
// in for a backtick, since the fixtures live in Go raw strings (which are backtick-delimited)
// and InSpec code_desc is itself backtick-quoted (e.g. Command: `sshd -T`).
func repOf(t *testing.T, controlsJSON string) *Report {
	t.Helper()
	var ctrls []Control
	if err := json.Unmarshal([]byte(strings.ReplaceAll(controlsJSON, "~", "`")), &ctrls); err != nil {
		t.Fatalf("unmarshal controls: %v", err)
	}
	r := &Report{}
	r.Platform.Name, r.Platform.Release = "debian", "12"
	r.Profiles = []struct {
		Title    string    `json:"title"`
		Version  string    `json:"version"`
		Controls []Control `json:"controls"`
	}{{Title: "t", Version: "1.0.0", Controls: ctrls}}
	return r
}

func byID(res []assessment.Result, id string) (assessment.Result, bool) {
	for _, r := range res {
		if r.Control == id {
			return r, true
		}
	}
	return assessment.Result{}, false
}

// TestAssessStatuses freezes the audit -> assessment status mapping: pass/fail, a waiver is a
// Fail carrying its justification, a guard that DECLARED a non-applicability is NotApplicable,
// and both a guard that said nothing and a control with no InSpec result are NotEvaluated. A gap
// must never read as a pass, and "skipped" alone is a gap: nobody can tell a requirement that
// does not address this host from a guard that is broken.
//
// The `na` case carries InSpec's real wire format, prefix included. It is the whole reason
// skipPayload exists: on a 653-control ubuntu2404 report, 22 of 22 declared non-applicabilities
// arrive wrapped in "Skipped control due to only_if condition: ", so a HasPrefix on the raw
// message matches none of them.
func TestAssessStatuses(t *testing.T) {
	rep := repOf(t, `[
	  {"id":"ok","title":"OK","impact":0.5,"tags":{"cis":"1.1"},
	   "results":[{"status":"passed","code_desc":"Command: ~sshd -T~ stdout"}]},
	  {"id":"bad","title":"Bad","impact":1.0,"tags":{"bp28":"R1","evidence":"effective-runtime"},
	   "results":[{"status":"failed","code_desc":"Command: ~sysctl -n x~ stdout","message":"\nexpected: \"1\"\n     got: \"0\"\n"}]},
	  {"id":"waived","title":"Waived","impact":0.7,
	   "waiver_data":{"justification":"accepted until Q3"},
	   "results":[{"status":"skipped","skip_message":"Skipped control due to waiver condition: accepted until Q3"}]},
	  {"id":"na","title":"NA","impact":0.7,
	   "results":[{"status":"skipped","skip_message":"Skipped control due to only_if condition: n/a: requires /home mounted"}]},
	  {"id":"mute","title":"Guard with no message","impact":0.7,
	   "results":[{"status":"skipped","skip_message":"Skipped control due to only_if condition."}]},
	  {"id":"hand","title":"Hand-written message","impact":0.7,
	   "results":[{"status":"skipped","skip_message":"Skipped control due to only_if condition: arm64 only"}]},
	  {"id":"empty","title":"Empty","impact":0.4,"results":[]}
	]`)

	res := Assess(rep, "host1", "", "")
	if len(res) != 7 {
		t.Fatalf("got %d results, want 7", len(res))
	}
	want := map[string]assessment.Status{
		"ok": assessment.Pass, "bad": assessment.Fail,
		"waived": assessment.Fail, "na": assessment.NotApplicable,
		"mute": assessment.NotEvaluated, "hand": assessment.NotEvaluated,
		"empty": assessment.NotEvaluated,
	}
	for id, ws := range want {
		r, ok := byID(res, id)
		if !ok {
			t.Fatalf("missing result %q", id)
		}
		if r.Status != ws {
			t.Errorf("%s: status = %q, want %q", id, r.Status, ws)
		}
	}

	// A waiver carries the justification (opposable accepted risk, distinct from N/A).
	if w, _ := byID(res, "waived"); w.Waiver == nil || w.Waiver.Justification != "accepted until Q3" {
		t.Errorf("waived: waiver = %+v, want justification set", w.Waiver)
	}
	if na, _ := byID(res, "na"); na.Waiver != nil {
		t.Errorf("na: waiver = %+v, want nil", na.Waiver)
	}
}

// TestAssessEvidence checks the effective-config evidence: the command source, the
// observed-vs-expected pair parsed from the failure, and the qualified-verdict triple.
func TestAssessEvidence(t *testing.T) {
	rep := repOf(t, `[
	  {"id":"bad","title":"Bad","impact":1.0,
	   "tags":{"cis":"1.2, 1.3","bp28":"R5","nist":"AC-1","evidence":"effective-runtime","reboot":"yes","domain":"Kernel"},
	   "results":[{"status":"failed","code_desc":"Command: ~sysctl -n net.ipv4.ip_forward~ stdout","message":"\nexpected: \"0\"\n     got: \"1\"\n"}]}
	]`)
	r, _ := byID(Assess(rep, "host1", "", ""), "bad")

	if r.Evidence.Source != "command:sysctl -n net.ipv4.ip_forward" {
		t.Errorf("source = %q", r.Evidence.Source)
	}
	if r.Evidence.Observed != "1" || r.Evidence.Expected != "0" {
		t.Errorf("observed/expected = %q/%q, want 1/0", r.Evidence.Observed, r.Evidence.Expected)
	}
	if r.Evidence.Type != "effective-runtime" {
		t.Errorf("type = %q", r.Evidence.Type)
	}
	// effective-runtime proves [running]; reboot:yes overrides the persistence axis to yes/yes.
	if r.Evidence.Proves != [3]string{"yes", "yes", "yes"} {
		t.Errorf("proves = %v, want [yes yes yes] (reboot override)", r.Evidence.Proves)
	}

	// References: exact framework ids, one per token, the bp28 slug expanded.
	want := []assessment.Reference{
		{Framework: "anssi-bp028", ID: "R5"},
		{Framework: "cis", ID: "1.2"},
		{Framework: "cis", ID: "1.3"},
		{Framework: "nist-800-53", ID: "AC-1"},
	}
	if len(r.References) != len(want) {
		t.Fatalf("references = %+v, want %+v", r.References, want)
	}
	for i, w := range want {
		if r.References[i] != w {
			t.Errorf("ref[%d] = %+v, want %+v", i, r.References[i], w)
		}
	}
}

// TestAssessNotEvaluatedOutOfScope: a control outside the requested standard is NotEvaluated in
// that run, never a silent pass, even though it passed at the InSpec level.
func TestAssessNotEvaluatedOutOfScope(t *testing.T) {
	rep := repOf(t, `[
	  {"id":"cisonly","impact":0.5,"tags":{"cis":"1.1"},"results":[{"status":"passed"}]},
	  {"id":"stigonly","impact":0.5,"tags":{"stig":"V-1"},"results":[{"status":"passed"}]}
	]`)
	res := Assess(rep, "host1", "cis", "")
	if r, _ := byID(res, "cisonly"); r.Status != assessment.Pass {
		t.Errorf("cisonly under --standard cis: %q, want pass", r.Status)
	}
	if r, _ := byID(res, "stigonly"); r.Status != assessment.NotEvaluated {
		t.Errorf("stigonly under --standard cis: %q, want not-evaluated", r.Status)
	}
}
