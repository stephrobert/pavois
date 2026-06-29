package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNormStatus(t *testing.T) {
	cases := []struct {
		in      string
		present bool
		want    string
	}{
		{"compliant", true, "pass"},
		{"gap", true, "fail"},
		{"not_applicable", true, "na"},
		{"", false, "absent"},
		{"compliant", false, "absent"}, // absence wins over value
	}
	for _, c := range cases {
		if got := normStatus(c.in, c.present); got != c.want {
			t.Errorf("normStatus(%q,%v) = %q, want %q", c.in, c.present, got, c.want)
		}
	}
}

func TestSevFromImpact(t *testing.T) {
	for _, c := range []struct {
		imp  float64
		want string
	}{{1.0, "critical"}, {0.7, "high"}, {0.5, "medium"}, {0.1, "low"}} {
		if got := sevFromImpact(c.imp); got != c.want {
			t.Errorf("sevFromImpact(%v) = %q, want %q", c.imp, got, c.want)
		}
	}
}

// inspecJSON builds a minimal InSpec report for one control with the given status.
func ctrl(id, status string) string {
	res := ""
	if status != "" { // "" => no results => not applicable
		res = `{"status":"` + status + `"}`
	}
	return `{"id":"` + id + `","title":"` + id + `","impact":0.5,"tags":{"domain":"Test"},"results":[` + res + `]}`
}

func writeReport(t *testing.T, dir, name string, controls ...string) string {
	t.Helper()
	body := `{"profiles":[{"title":"t","version":"0.1.0","controls":[` + strings.Join(controls, ",") + `]}]}`
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestDiffTransitions(t *testing.T) {
	dir := t.TempDir()
	before := writeReport(t, dir, "before.json",
		ctrl("c-fix", "failed"),       // fail -> pass
		ctrl("c-reg", "passed"),       // pass -> fail (regression)
		ctrl("c-stay-fail", "failed"), // fail -> fail
		ctrl("c-newapp", ""),          // na -> pass
		ctrl("c-gone", "failed"),      // present before, absent after
	)
	after := writeReport(t, dir, "after.json",
		ctrl("c-fix", "passed"),
		ctrl("c-reg", "failed"),
		ctrl("c-stay-fail", "failed"),
		ctrl("c-newapp", "passed"),
		ctrl("c-brand-new", "passed"), // absent -> pass
	)

	var out bytes.Buffer
	diffCmd.SetOut(&out)
	diffHTMLOut, diffJSONOut = "", ""
	if err := runDiff(diffCmd, []string{before, after}); err != nil {
		t.Fatal(err)
	}
	got := out.String()

	for _, want := range []string{
		"Failed -> passed (fixed)",
		"Passed -> failed (regression)",
		"Failed -> failed (still failing)",
		"Newly applicable -> passed",
		"New control -> passed",
		"c-reg", // regression id surfaced
	} {
		if !strings.Contains(got, want) {
			t.Errorf("diff output missing %q\n---\n%s", want, got)
		}
	}
}
