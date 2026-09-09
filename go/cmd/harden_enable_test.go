package cmd

import "testing"

// preEnable decides what `harden plan --enable` writes as `apply: true`. The cases that matter are
// the ones it must REFUSE to arm: enabling a gap no apply can close makes a convergence loop spin
// forever, and enabling a dangerous one without a human reading it is how you lock yourself out.
func TestPreEnable(t *testing.T) {
	cases := []struct {
		name             string
		selector, status string
		class, danger    string
		want             bool
	}{
		// nothing is armed unless asked
		{"default selector arms nothing", "none", "gap", "", "", false},
		{"empty selector arms nothing", "", "gap", "", "", false},

		// auto: the gaps an apply can actually close
		{"auto arms a plain gap", "auto", "gap", "", "", true},
		{"auto skips a dangerous gap", "auto", "gap", "", "locks you out of SSH", false},
		{"auto skips install-time", "auto", "gap", "install-time", "", false},
		{"auto skips kernel-build", "auto", "gap", "kernel-build", "", false},
		{"auto skips manual", "auto", "gap", "manual", "", false},

		// all: adds the dangerous ones, still unacknowledged, so apply keeps refusing them
		{"all arms a dangerous gap", "all", "gap", "", "reboots into a locked GRUB", true},
		{"all still skips install-time", "all", "gap", "install-time", "", false},

		// a compliant control carries its remediation, but arming it would rewrite what is fine
		{"auto never arms a compliant control", "auto", "compliant", "", "", false},
		{"all never arms a compliant control", "all", "compliant", "", "", false},
		{"never arms a not_applicable control", "auto", "not_applicable", "", "", false},

		// a typo is rejected upstream, but the helper must not fail open either
		{"unknown selector arms nothing", "sfae", "gap", "", "", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := preEnable(c.selector, c.status, c.class, c.danger); got != c.want {
				t.Fatalf("preEnable(%q, %q, class=%q, danger=%q) = %v, want %v",
					c.selector, c.status, c.class, c.danger, got, c.want)
			}
		})
	}
}
