package audit

import (
	"encoding/json"
	"testing"
)

func TestRemediationClass(t *testing.T) {
	tc := func(id, domain, evidence string) Control {
		return Control{ID: id, Tags: map[string]any{"domain": domain, "evidence": evidence}}
	}
	cases := []struct {
		c    Control
		want string
	}{
		{tc("kconfig-debug-fs", "Kernel build", "filesystem-state"), "kernel-build"},
		{tc("mount-home-nodev", "Mounts", "persistent-config"), "install-time"},
		{tc("partition-var", "Filesystem", "inventory-state"), "install-time"},
		{tc("kmod-loading-disabled", "Kernel modules", "effective-runtime"), "dangerous"},
		{tc("cmdline-iommu-force", "Kernel command line", "effective-runtime"), "dangerous"},
		{tc("ssh-disable-root-login", "SSH", "effective-runtime"), "auto"},
		{tc("some-manual-control", "Hardening (misc)", "manual"), "manual"},
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
		{"id":"kmod-loading-disabled","impact":0.5,"tags":{"domain":"Kernel modules"},"results":[{"status":"passed"}]},
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
