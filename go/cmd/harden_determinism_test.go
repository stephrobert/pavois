package cmd

import "testing"

// compileRecipe used to walk `p.Rules`, a map, so everything it appended to a list came out in a
// different order on every run: the `pavois-conf-*` executes, the PAM edits, the raw execs. The
// same plan compiled to a different recipe each time.
//
// That is not cosmetic. The restore point photographs what the recipe will touch, `pavois bundle`
// digests it into evidence an operator signs, and PAM is a stack where order is correctness (a
// pwhistory line inserted after pam_unix does nothing). It also makes "same plan, same package"
// impossible, which is what a generated configuration package needs (#198).
//
// The fixture must use remediations that ACCUMULATE INTO A LIST: conf_line, pam_line, exec.
// Resources that land in a map keyed by file (sysctl, keyval, sshd_setting) are re-sorted at
// emission, so they hide the defect: a first version of this test used those and passed even with
// the sort removed, which the falsification harness caught (tools/falsify.yml).
//
// Go randomises map iteration deliberately, so ten compiles of an eight-rule plan agreeing by
// chance is negligible.
func TestCompileRecipeIsDeterministic(t *testing.T) {
	plan := loadPlan(t, `
target: pavois@host
os: debian12
rules:
  zz-last-alphabetically:
    apply: true
    status: gap
    remediation:
      resource: conf_line
      file: /etc/login.defs
      key: UMASK
      value: "077"
  mm-middle:
    apply: true
    status: gap
    remediation:
      resource: conf_line
      file: /etc/login.defs
      key: PASS_MAX_DAYS
      value: "365"
  aa-first:
    apply: true
    status: gap
    remediation:
      resource: conf_line
      file: /etc/login.defs
      key: PASS_MIN_DAYS
      value: "1"
  pam-pwquality:
    apply: true
    status: gap
    remediation:
      resource: pam_line
      file: /etc/pam.d/common-password
      module: pam_pwquality.so
      before: pam_unix.so
      line: password requisite pam_pwquality.so retry=3
  pam-pwhistory:
    apply: true
    status: gap
    remediation:
      resource: pam_line
      file: /etc/pam.d/common-password
      module: pam_pwhistory.so
      before: pam_unix.so
      line: password required pam_pwhistory.so remember=5
  exec-perms-shadow:
    apply: true
    status: gap
    remediation:
      resource: exec
      name: chmod-shadow
      command: chmod 0640 /etc/shadow
      not_if: "stat -c %a /etc/shadow | grep -qx 640"
  exec-perms-gshadow:
    apply: true
    status: gap
    remediation:
      resource: exec
      name: chmod-gshadow
      command: chmod 0640 /etc/gshadow
      not_if: "stat -c %a /etc/gshadow | grep -qx 640"
  exec-perms-passwd:
    apply: true
    status: gap
    remediation:
      resource: exec
      name: chmod-passwd
      command: chmod 0644 /etc/passwd
      not_if: "stat -c %a /etc/passwd | grep -qx 644"
`)

	first, count, _, _, conflicts := compileRecipe(plan, "", "", "", "")
	if len(conflicts) != 0 {
		t.Fatalf("unexpected conflicts: %v", conflicts)
	}
	if count == 0 {
		t.Fatal("count = 0, the fixture compiled nothing")
	}

	for i := 2; i <= 10; i++ {
		got, _, _, _, _ := compileRecipe(plan, "", "", "", "")
		if got != first {
			t.Fatalf("compile #%d differs from #1: the recipe is not reproducible.\n"+
				"first:\n%s\n\ncompile #%d:\n%s", i, first, i, got)
		}
	}
}
