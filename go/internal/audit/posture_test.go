package audit

import (
	"encoding/json"
	"testing"
)

func TestRemediationClass(t *testing.T) {
	// The class comes from the RULE (tag remediation_class), not from a list of ids in Go.
	tagged := func(id, class string) Control {
		return Control{ID: id, Tags: map[string]any{"remediation_class": class}}
	}
	// Fallbacks, for a corpus rendered before the tag existed.
	legacy := func(id, domain, evidence, danger string) Control {
		return Control{ID: id, Tags: map[string]any{
			"domain": domain, "evidence": evidence, "danger": danger,
		}}
	}
	cases := []struct {
		c    Control
		want string
	}{
		{tagged("kconfig-debug-fs", "kernel-build"), "kernel-build"},
		{tagged("mount-home-nodev", "install-time"), "install-time"},
		{tagged("kmod-loading-disabled", "dangerous"), "dangerous"},
		{tagged("ssh-disable-root-login", "auto"), "auto"},
		{tagged("some-manual-control", "manual"), "manual"},
		// the rule WINS over any heuristic the id might suggest
		{Control{ID: "partition-var", Tags: map[string]any{
			"remediation_class": "auto", "domain": "Mounts",
		}}, "auto"},
		{legacy("kconfig-x", "Kernel build", "", ""), "kernel-build"},
		{legacy("partition-var", "Filesystem", "inventory-state", ""), "install-time"},
		{legacy("kmod-loading-disabled", "Kernel modules", "", "bricks the host"), "dangerous"},
		{legacy("ssh-x", "SSH", "effective-runtime", ""), "auto"},
		{legacy("manual-x", "Hardening (misc)", "manual", ""), "manual"},
	}
	for _, c := range cases {
		if got := RemediationClass(c.c); got != c.want {
			t.Errorf("RemediationClass(%s) = %s, want %s", c.c.ID, got, c.want)
		}
	}
}

func TestBreakdown(t *testing.T) {
	// One control per class: auto fails (medium), kernel-build fails, install-time fails,
	// dangerous passes. The remediable scope excludes kernel-build + install-time, so its
	// only failure is the auto one.
	j := `{"profiles":[{"controls":[
		{"id":"ssh-x","impact":0.5,"tags":{"domain":"SSH","evidence":"effective-runtime"},"results":[{"status":"failed"}]},
		{"id":"kconfig-x","impact":0.5,"tags":{"domain":"Kernel build"},"results":[{"status":"failed"}]},
		{"id":"mount-x","impact":0.5,"tags":{"domain":"Mounts"},"results":[{"status":"failed"}]},
		{"id":"kmod-loading-disabled","impact":0.5,"tags":{"domain":"Kernel modules","remediation_class":"dangerous"},"results":[{"status":"passed"}]},
		{"id":"pkg-y","impact":0.5,"tags":{"domain":"Packages"},"results":[{"status":"passed"}]}
	]}]}`
	var r Report
	if err := json.Unmarshal([]byte(j), &r); err != nil {
		t.Fatal(err)
	}
	p := Breakdown(&r, "", "")

	got := map[string]ClassStat{}
	for _, c := range p.Classes {
		got[c.Class] = c
	}
	if got["auto"].Total != 2 || got["auto"].Failed != 1 {
		t.Errorf("auto = %+v, want total 2 failed 1", got["auto"])
	}
	if got["kernel-build"].Failed != 1 || got["install-time"].Failed != 1 {
		t.Errorf("kernel-build/install-time not counted: %+v", got)
	}
	if got["dangerous"].Passed != 1 {
		t.Errorf("dangerous = %+v, want passed 1", got["dangerous"])
	}
	// Remediable scope = auto + dangerous = 3 controls, 1 failure (the medium ssh-x).
	if p.RemediableTotal != 3 || p.RemediablePassed != 2 {
		t.Errorf("remediable = %d/%d, want 2/3", p.RemediablePassed, p.RemediableTotal)
	}
	if p.RemediableGrade == "" {
		t.Error("remediable grade not computed")
	}
}
