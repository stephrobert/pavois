package audit

import (
	"encoding/json"
	"testing"
)

// The rule this file freezes: a control leaves the denominator as "not applicable" ONLY when it
// said so. Everything else that leaves it is unmeasured, and stays visible.
//
// It exists because the opposite was true and cost nothing to anybody's eye: audit.go filed ANY
// skip as NotApplicable, so a guard whose condition was wrong, a guard with no message, and a
// requirement the norm genuinely does not address all produced the same silent line.
func TestSkipPayloadStripsInSpecsOwnPrefix(t *testing.T) {
	cases := []struct{ in, want string }{
		// The wire format, which is the whole point: the author wrote `n/a: requires /home
		// mounted` and InSpec hands over its own sentence with that appended.
		{"Skipped control due to only_if condition: n/a: requires /home mounted", "n/a: requires /home mounted"},
		{"Skipped control due to waiver condition: accepted until Q3", "accepted until Q3"},
		// A guard that fired and explained nothing. 81 of these on a real ubuntu2404 run.
		{"Skipped control due to only_if condition.", ""},
		{"Skipped control due to only_if condition", ""},
		// A message that never went through InSpec is returned untouched.
		{"n/a: requires bare metal", "n/a: requires bare metal"},
		{"", ""},
	}
	for _, c := range cases {
		if got := skipPayload(c.in); got != c.want {
			t.Errorf("skipPayload(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// ctrl builds one Control from JSON, because Control's Results and WaiverData are anonymous
// inline structs: going through the decoder is both shorter and closer to what a scan produces.
func ctrl(t *testing.T, j string) Control {
	t.Helper()
	var c Control
	if err := json.Unmarshal([]byte(j), &c); err != nil {
		t.Fatalf("unmarshal control: %v", err)
	}
	return c
}

func skippedWith(t *testing.T, msg string) Control {
	t.Helper()
	b, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("marshal message: %v", err)
	}
	return ctrl(t, `{"id":"x","results":[{"status":"skipped","skip_message":`+string(b)+`}]}`)
}

func TestDeclaresNA(t *testing.T) {
	cases := []struct {
		name string
		c    Control
		want bool
	}{
		{"declared, as InSpec delivers it",
			skippedWith(t, "Skipped control due to only_if condition: n/a: requires /home mounted"), true},
		{"declared, unwrapped", skippedWith(t, "n/a: requires bare metal"), true},
		{"a guard that said nothing", skippedWith(t, "Skipped control due to only_if condition."), false},
		{"a hand-written message that declares nothing",
			skippedWith(t, "Skipped control due to only_if condition: arm64 only"), false},
		// The trap: a message that MENTIONS the marker without leading with it. A control whose
		// author wrote "this is not n/a: it must be checked" is not declaring anything.
		{"the marker somewhere in the middle",
			skippedWith(t, "Skipped control due to only_if condition: this is not n/a: check it"), false},
		{"no result at all", ctrl(t, `{"id":"x"}`), false},
		{"a passing control is never n/a", ctrl(t, `{"id":"x","results":[{"status":"passed"}]}`), false},
	}
	for _, c := range cases {
		if got := declaresNA(c.c); got != c.want {
			t.Errorf("%s: declaresNA = %v, want %v", c.name, got, c.want)
		}
	}
}

const mixedControls = `[
  {"id":"pass","impact":0.5,"results":[{"status":"passed"}]},
  {"id":"fail","impact":0.7,"results":[{"status":"failed"}]},
  {"id":"declared","impact":0.7,
   "results":[{"status":"skipped","skip_message":"Skipped control due to only_if condition: n/a: requires /home mounted"}]},
  {"id":"mute1","impact":0.7,
   "results":[{"status":"skipped","skip_message":"Skipped control due to only_if condition."}]},
  {"id":"mute2","impact":0.7,
   "results":[{"status":"skipped","skip_message":"Skipped control due to only_if condition: arm64 only"}]},
  {"id":"noresult","impact":0.7,"results":[]},
  {"id":"waived","impact":0.7,"waiver_data":{"justification":"accepted until Q3"},
   "results":[{"status":"skipped","skip_message":"Skipped control due to waiver condition: accepted until Q3"}]}
]`

// Evaluate is where the three buckets have to stay apart, because the scorecard reads them.
func TestEvaluateSeparatesNAFromUnmeasured(t *testing.T) {
	res := Evaluate(repOf(t, mixedControls), "host1", "", "")

	for _, c := range []struct {
		name      string
		got, want int
	}{
		{"Passed", res.Passed, 1},
		{"Total (scored: pass + fail)", res.Total, 2},
		{"NotApplicable (declared only)", res.NotApplicable, 1},
		{"Unmeasured (two mute guards + one with no result)", res.Unmeasured, 3},
		{"Waived", res.Waived, 1},
	} {
		if c.got != c.want {
			t.Errorf("%s = %d, want %d", c.name, c.got, c.want)
		}
	}

	// Every control is accounted for exactly once. Without this, a bucket could be dropped and
	// each individual count above would still look right.
	if sum := res.Total + res.NotApplicable + res.Unmeasured + res.Waived; sum != 7 {
		t.Errorf("the buckets account for %d of 7 controls", sum)
	}
}

// The grade must NOT move. An unknown is not a failure, so reclassifying 86 controls out of n/a
// and into unmeasured changes what the report SAYS and not what it scores. If this test ever goes
// red, the change stopped being a reporting fix and became a scoring change.
func TestUnmeasuredDoesNotTouchTheScore(t *testing.T) {
	const base = `[
	  {"id":"pass","impact":0.5,"results":[{"status":"passed"}]},
	  {"id":"fail","impact":0.9,"results":[{"status":"failed"}]}
	]`
	const plusMute = `[
	  {"id":"pass","impact":0.5,"results":[{"status":"passed"}]},
	  {"id":"fail","impact":0.9,"results":[{"status":"failed"}]},
	  {"id":"mute","impact":0.9,
	   "results":[{"status":"skipped","skip_message":"Skipped control due to only_if condition."}]}
	]`

	without := Evaluate(repOf(t, base), "h", "", "")
	with := Evaluate(repOf(t, plusMute), "h", "", "")

	wasLetter, wasPts := Grade(without.Summary)
	nowLetter, nowPts := Grade(with.Summary)
	if wasLetter != nowLetter || wasPts != nowPts {
		t.Errorf("adding an unmeasured control moved the grade: %s (%d) -> %s (%d)",
			wasLetter, wasPts, nowLetter, nowPts)
	}
	if with.Unmeasured != 1 {
		t.Errorf("the unmeasured control was not counted: %d", with.Unmeasured)
	}
}
