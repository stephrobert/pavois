package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// `--from` re-grades an archived report. Its own help says "no scan", and the handbook promises it
// works "without touching the host", so it must not need a target, a transport or a CINC engine.
//
// It did. The profile was chosen by probing the machine named on the command line, even with
// --from, so `scan local --from report.json` refused to run anywhere cinc-auditor was not
// installed. It went unnoticed because the machine that runs it usually is a scanning station; the
// CI runner is not, and that is what found it. Re-grading an archived report is precisely the case
// where the machine may be long gone.
//
// profileForPlatform is the half that does not probe: platform in, profile out. If someone routes
// --from back through detection, this stops compiling or stops passing.
func TestProfileForPlatformNeedsNoMachine(t *testing.T) {
	root := findRoot()
	if _, err := os.Stat(filepath.Join(root, "profiles", "linux", "debian12")); err != nil {
		t.Skip("rendered corpus absent (mise run render); nothing to map onto")
	}

	cases := []struct {
		name, release, wantProfile, wantDetected string
	}{
		{"debian", "12.15", "linux/debian12", "debian 12.15"},
		{"debian", "13.7", "linux/debian13", "debian 13.7"},
		{"ubuntu", "24.04", "linux/ubuntu2404", "ubuntu 24.04"},
	}
	for _, c := range cases {
		profile, detected, why := profileForPlatform(root, c.name, c.release)
		if profile != c.wantProfile {
			t.Errorf("profileForPlatform(%q, %q) = %q, want %q (why: %q)",
				c.name, c.release, profile, c.wantProfile, why)
		}
		if detected != c.wantDetected {
			t.Errorf("profileForPlatform(%q, %q) detected %q, want %q",
				c.name, c.release, detected, c.wantDetected)
		}
		if why != "" {
			t.Errorf("profileForPlatform(%q, %q) should not explain a failure, got %q",
				c.name, c.release, why)
		}
	}
}

// An unknown platform must say so rather than silently pick a profile: grading a report against the
// wrong OS produces a full set of confident, wrong verdicts.
func TestProfileForPlatformUnknownIsRefused(t *testing.T) {
	profile, detected, why := profileForPlatform(t.TempDir(), "plan9", "4")
	if profile != "" {
		t.Errorf("an unknown platform must not resolve to a profile, got %q", profile)
	}
	if detected != "plan9 4" {
		t.Errorf("the platform should still be reported, got %q", detected)
	}
	if why == "" {
		t.Error("a refusal must carry a reason")
	}
}
