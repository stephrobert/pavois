package cmd

import (
	"strings"
	"testing"

	"gopkg.in/yaml.v3"
)

// loadPlan unmarshals a YAML plan into planFile. The Rules map uses an anonymous
// struct, so tests build fixtures through the real input format (YAML) rather than
// struct literals — which also exercises the exact decoding path used in production.
func loadPlan(t *testing.T, src string) planFile {
	t.Helper()
	var p planFile
	if err := yaml.Unmarshal([]byte(src), &p); err != nil {
		t.Fatalf("unmarshal plan: %v", err)
	}
	return p
}

func TestS(t *testing.T) {
	tests := []struct {
		name string
		in   any
		want string
	}{
		{"nil is empty (not <nil>)", nil, ""},
		{"string trimmed", "  abc  ", "abc"},
		{"int", 42, "42"},
		{"bool", true, "true"},
		{"empty string", "", ""},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := s(tc.in); got != tc.want {
				t.Fatalf("s(%v) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

func TestSortedKeys(t *testing.T) {
	in := map[string]bool{"b": true, "a": true, "": true, "c": true}
	got := sortedKeys(in)
	want := []string{"a", "b", "c"} // empty key dropped, sorted ascending
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("sortedKeys = %v, want %v", got, want)
	}
}

func TestSortedKeysS(t *testing.T) {
	in := map[string]string{"z": "1", "a": "2", "m": "3"}
	got := sortedKeysS(in)
	if strings.Join(got, ",") != "a,m,z" {
		t.Fatalf("sortedKeysS = %v, want [a m z]", got)
	}
}

func TestSSHOptsFor(t *testing.T) {
	base := sshOptsFor("")
	joined := strings.Join(base, " ")
	for _, want := range []string{"StrictHostKeyChecking=no", "ConnectTimeout=15", "-F /dev/null"} {
		if !strings.Contains(joined, want) {
			t.Errorf("sshOptsFor() missing %q in %q", want, joined)
		}
	}
	if strings.Contains(joined, "-i") {
		t.Errorf("sshOptsFor(\"\") must not add -i: %q", joined)
	}

	withKey := sshOptsFor("/path/key")
	jk := strings.Join(withKey, " ")
	if !strings.Contains(jk, "-i /path/key") {
		t.Errorf("sshOptsFor(key) must add -i <key>: %q", jk)
	}
}

func TestSSHTTY(t *testing.T) {
	got := sshTTY("user@host", "echo hi")
	if got[0] != "-tt" {
		t.Errorf("sshTTY must force a pty (-tt first): %v", got)
	}
	if got[len(got)-1] != "echo hi" {
		t.Errorf("sshTTY must end with the command: %v", got)
	}
	if got[len(got)-2] != "user@host" {
		t.Errorf("sshTTY must place the target before the command: %v", got)
	}
}

func TestGenPassword(t *testing.T) {
	const charset = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#%^*-_=+"
	for _, n := range []int{1, 16, 32} {
		pw := genPassword(n)
		if len(pw) != n {
			t.Fatalf("genPassword(%d) length = %d", n, len(pw))
		}
		for _, c := range pw {
			if !strings.ContainsRune(charset, c) {
				t.Fatalf("genPassword produced out-of-charset rune %q", c)
			}
		}
	}
	// Two calls must (overwhelmingly) differ — guards against a constant/zeroed buffer.
	a, b := genPassword(24), genPassword(24)
	if a == b {
		t.Error("genPassword returned identical values twice")
	}
}

func TestCompileRecipeBasicResources(t *testing.T) {
	plan := loadPlan(t, `
target: pavois@host
os: debian12
baseline_packages:
  - name: auditd
    apply: true
  - name: skipped-pkg
    apply: false
rules:
  ssh-permitrootlogin:
    apply: true
    status: gap
    remediation:
      resource: sshd_setting
      directive: PermitRootLogin
      value: "no"
  svc-telnet-removed:
    apply: true
    status: gap
    remediation:
      resource: package
      action: remove
      name: telnetd
  sysctl-aslr:
    apply: true
    status: gap
    remediation:
      resource: sysctl
      key: kernel.randomize_va_space
      value: "2"
`)

	recipe, count, reboot, pending, conflicts := compileRecipe(plan, "", "", "")

	if len(conflicts) != 0 {
		t.Fatalf("unexpected conflicts: %v", conflicts)
	}
	if pending != 0 {
		t.Errorf("pending = %d, want 0", pending)
	}
	if reboot {
		t.Errorf("reboot = true, want false (no reboot_required set)")
	}
	if count == 0 {
		t.Fatalf("count = 0, expected enabled items")
	}

	// Baseline package installs (apply:true only) go into ONE batched install execute.
	if !strings.Contains(recipe, "pavois-install-packages") || !strings.Contains(recipe, "auditd") {
		t.Error("recipe missing batched auditd install")
	}
	if strings.Contains(recipe, "skipped-pkg") {
		t.Error("recipe must not include a baseline package with apply:false")
	}
	// sshd drop-in carries the directive/value.
	if !strings.Contains(recipe, "PermitRootLogin no") {
		t.Errorf("recipe missing sshd directive:\n%s", recipe)
	}
	// package remove.
	if !strings.Contains(recipe, `package "telnetd" do`) || !strings.Contains(recipe, "action :remove") {
		t.Errorf("recipe missing telnetd removal:\n%s", recipe)
	}
	// sysctl drop-in.
	if !strings.Contains(recipe, "kernel.randomize_va_space = 2") {
		t.Errorf("recipe missing sysctl line:\n%s", recipe)
	}
	// No bash, ever (CLAUDE.md invariant for compiled resources).
	if strings.Contains(recipe, "#!/bin/bash") {
		t.Error("recipe must not embed a bash shebang")
	}
}

func TestCompileRecipeConflictDetection(t *testing.T) {
	plan := loadPlan(t, `
target: pavois@host
rules:
  a:
    apply: true
    status: gap
    remediation:
      resource: sysctl
      key: net.ipv4.ip_forward
      value: "0"
  b:
    apply: true
    status: gap
    remediation:
      resource: sysctl
      key: net.ipv4.ip_forward
      value: "1"
`)
	_, _, _, _, conflicts := compileRecipe(plan, "", "", "")
	if len(conflicts) == 0 {
		t.Fatal("expected a conflict for the same sysctl key with two values")
	}
	if !strings.Contains(conflicts[0], "net.ipv4.ip_forward") {
		t.Errorf("conflict should name the key: %v", conflicts)
	}
}

func TestCompileRecipePackageInstallVsRemoveConflict(t *testing.T) {
	plan := loadPlan(t, `
target: pavois@host
rules:
  add:
    apply: true
    status: gap
    remediation:
      resource: package
      name: nftables
  drop:
    apply: true
    status: gap
    remediation:
      resource: package
      action: remove
      name: nftables
`)
	_, _, _, _, conflicts := compileRecipe(plan, "", "", "")
	found := false
	for _, c := range conflicts {
		if strings.Contains(c, "nftables") && strings.Contains(c, "install vs remove") {
			found = true
		}
	}
	if !found {
		t.Errorf("expected install-vs-remove conflict for nftables, got: %v", conflicts)
	}
}

func TestCompileRecipeRebootAndPending(t *testing.T) {
	plan := loadPlan(t, `
target: pavois@host
rules:
  needs-reboot:
    apply: true
    status: gap
    remediation:
      resource: kernel_cmdline
      param: audit=1
      reboot_required: true
  no-remediation-yet:
    apply: true
    status: gap
`)
	_, _, reboot, pending, conflicts := compileRecipe(plan, "", "", "")
	if len(conflicts) != 0 {
		t.Fatalf("unexpected conflicts: %v", conflicts)
	}
	if !reboot {
		t.Error("reboot should be true when an enabled remediation sets reboot_required")
	}
	if pending != 1 {
		t.Errorf("pending = %d, want 1 (the rule with no remediation)", pending)
	}
}

func TestCompileRecipeDisabledRuleSkipped(t *testing.T) {
	plan := loadPlan(t, `
target: pavois@host
rules:
  off:
    apply: false
    status: gap
    remediation:
      resource: package
      name: should-not-appear
`)
	recipe, count, _, _, _ := compileRecipe(plan, "", "", "")
	if strings.Contains(recipe, "should-not-appear") {
		t.Error("a rule with apply:false must not emit resources")
	}
	if count != 0 {
		t.Errorf("count = %d, want 0 for an all-disabled plan", count)
	}
}

// Aggregated drop-ins must include COMPLIANT controls' settings too, so applying a
// subset never regresses an already-passing directive (e.g. re-enabling root SSH).
func TestCompileRecipeKeepsCompliantAggregated(t *testing.T) {
	plan := loadPlan(t, `
target: pavois@host
rules:
  ssh-gap:
    apply: true
    status: gap
    remediation:
      resource: sshd_setting
      directive: PermitRootLogin
      value: "no"
  ssh-compliant:
    apply: false
    status: compliant
    remediation:
      resource: sshd_setting
      directive: PasswordAuthentication
      value: "no"
`)
	recipe, _, _, _, conflicts := compileRecipe(plan, "", "", "")
	if len(conflicts) != 0 {
		t.Fatalf("unexpected conflicts: %v", conflicts)
	}
	if !strings.Contains(recipe, "PermitRootLogin no") {
		t.Error("recipe missing the enabled sshd gap")
	}
	if !strings.Contains(recipe, "PasswordAuthentication no") {
		t.Error("recipe must keep the COMPLIANT aggregated sshd setting to avoid regression")
	}
}
