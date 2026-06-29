package cmd

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestBundle(t *testing.T) {
	dir := t.TempDir()
	before := writeReport(t, dir, "before.json",
		ctrl("c-fix", "failed"), // fail -> pass
		ctrl("c-reg", "passed"), // pass -> fail (regression)
	)
	after := writeReport(t, dir, "after.json",
		ctrl("c-fix", "passed"),
		ctrl("c-reg", "failed"),
	)

	out := filepath.Join(dir, "ev")
	bundleOut = out
	bundlePlan, bundleReports, bundleReboot, bundleException = "", nil, "", ""
	var buf bytes.Buffer
	bundleCmd.SetOut(&buf)
	if err := runBundle(bundleCmd, []string{before, after}); err != nil {
		t.Fatal(err)
	}

	// manifest is valid and well-formed.
	raw, err := os.ReadFile(filepath.Join(out, "manifest.json"))
	if err != nil {
		t.Fatalf("manifest: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("manifest not valid JSON: %v", err)
	}
	if m["format"] != "pavois-evidence-bundle/v1" {
		t.Errorf("format = %v", m["format"])
	}
	camp, ok := m["campaign"].(map[string]any)
	if !ok || camp["fixed"].(float64) != 1 {
		t.Errorf("campaign.fixed = %v, want 1", camp["fixed"])
	}
	regs, _ := camp["regressions"].([]any)
	if len(regs) != 1 || regs[0] != "c-reg" {
		t.Errorf("regressions = %v, want [c-reg]", regs)
	}

	// every required artifact is present, plus the integrity files.
	for _, f := range []string{"before.json", "after.json", "campaign-delta.json", "manifest.json", "checksums.txt"} {
		if _, err := os.Stat(filepath.Join(out, f)); err != nil {
			t.Errorf("missing bundle file %s", f)
		}
	}
}
