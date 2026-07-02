package audit

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestSeverity(t *testing.T) {
	cases := []struct {
		impact float64
		want   string
	}{
		{1.0, "critical"},
		{0.9, "critical"},
		{0.89, "high"},
		{0.7, "high"},
		{0.5, "medium"},
		{0.4, "medium"},
		{0.39, "low"},
		{0.0, "low"},
	}
	for _, c := range cases {
		if got := severity(c.impact); got != c.want {
			t.Errorf("severity(%g) = %q, want %q", c.impact, got, c.want)
		}
	}
}

// ctl builds a Control through JSON so the anonymous Results field can be populated.
func ctl(t *testing.T, raw string) Control {
	t.Helper()
	var c Control
	if err := json.Unmarshal([]byte(raw), &c); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return c
}

func TestStatus(t *testing.T) {
	cases := []struct {
		name, raw, want string
	}{
		{"empty", `{"id":"x"}`, "empty"},
		{"failed wins", `{"id":"x","results":[{"status":"passed"},{"status":"failed"}]}`, "failed"},
		{"all skipped", `{"id":"x","results":[{"status":"skipped"}]}`, "skipped"},
		{"passed", `{"id":"x","results":[{"status":"passed"}]}`, "passed"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := status(ctl(t, c.raw)); got != c.want {
				t.Errorf("status = %q, want %q", got, c.want)
			}
		})
	}
}

func TestApplicable(t *testing.T) {
	c := ctl(t, `{"id":"x","tags":{"cis":"1.1.1"}}`)
	cases := []struct {
		standard string
		want     bool
	}{
		{"", true},      // no filter
		{"all", true},   // explicit all
		{"cis", true},   // tagged
		{"bp28", false}, // not tagged
	}
	for _, tc := range cases {
		if got := applicable(c, tc.standard); got != tc.want {
			t.Errorf("applicable(%q) = %v, want %v", tc.standard, got, tc.want)
		}
	}
}

func TestInLevel(t *testing.T) {
	// CIS level 2 control.
	c := ctl(t, `{"id":"x","tags":{"cis":"1.1","level_cis":"2"}}`)
	cases := []struct {
		name            string
		standard, level string
		want            bool
	}{
		{"no level filter", "cis", "", true},
		{"all level", "cis", "all", true},
		{"l2 in l2", "cis", "2", true},
		{"l2 not in l1", "cis", "1", false},
		{"unknown standard order -> included", "nist", "x", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := inLevel(c, tc.standard, tc.level); got != tc.want {
				t.Errorf("inLevel(%q,%q) = %v, want %v", tc.standard, tc.level, got, tc.want)
			}
		})
	}

	// A control without a level tag is unconstrained (included at any level).
	untagged := ctl(t, `{"id":"y","tags":{"cis":"1.2"}}`)
	if !inLevel(untagged, "cis", "1") {
		t.Error("untagged control should be included at any level")
	}
}

func TestIndexOf(t *testing.T) {
	order := []string{"minimal", "intermediary", "enhanced", "high"}
	if got := indexOf(order, "enhanced"); got != 2 {
		t.Errorf("indexOf = %d, want 2", got)
	}
	if got := indexOf(order, "absent"); got != len(order) {
		t.Errorf("indexOf(absent) = %d, want %d (past end)", got, len(order))
	}
}

func TestEvaluateAndHeadline(t *testing.T) {
	var r Report
	raw := `{
		"platform":{"name":"debian","release":"12"},
		"profiles":[{"title":"P","controls":[
			{"id":"crit-fail","impact":0.95,"tags":{"cis":"1","evidence":"persistent-config","reboot":"yes"},
			 "results":[{"status":"failed","code_desc":"x"}]},
			{"id":"high-pass","impact":0.7,"tags":{"cis":"2","evidence":"persistent-config","reboot":"yes"},
			 "results":[{"status":"passed","code_desc":"x"}]},
			{"id":"bp28-only","impact":0.5,"tags":{"bp28":"R1","evidence":"persistent-config","reboot":"yes"},
			 "results":[{"status":"passed","code_desc":"x"}]}
		]}]
	}`
	if err := json.Unmarshal([]byte(raw), &r); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	// Filter to CIS: the bp28-only control is excluded.
	res := Evaluate(&r, "host", "cis", "")
	if res.Total != 2 {
		t.Errorf("Total = %d, want 2 (cis-tagged pass+fail)", res.Total)
	}
	if res.Passed != 1 {
		t.Errorf("Passed = %d, want 1", res.Passed)
	}
	if len(res.Findings) != 1 {
		t.Errorf("Findings = %d, want 1 (the failed control)", len(res.Findings))
	}
	if res.OS != "debian 12" {
		t.Errorf("OS = %q, want \"debian 12\"", res.OS)
	}

	// No standard filter: all three controls are in scope.
	all := Evaluate(&r, "host", "", "")
	if all.Total != 3 {
		t.Errorf("all Total = %d, want 3", all.Total)
	}

	headline := Headline(res)
	if !strings.HasPrefix(headline, "Grade ") {
		t.Errorf("Headline should start with \"Grade \": %q", headline)
	}
	if !strings.Contains(headline, "1/2 compliant") {
		t.Errorf("Headline should report passed/total: %q", headline)
	}
}
