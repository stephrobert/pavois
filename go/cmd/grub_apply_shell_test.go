package cmd

import (
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// The bootloader command is assembled by string concatenation in Go, runs as one line of shell on
// the target, and has been edited by hand many times. A quoting mistake in it does not fail a
// build, a lint or a unit test: it fails on somebody's machine, inside `ignore_failure true`, where
// the only trace is a line nobody reads.
//
// So the generated command is handed to `sh -n`. That is the shell's own parser, on the exact
// string the target will receive, which no amount of reading the Go source can replace.
func TestGrubApplyCommandIsValidShell(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("no sh on this machine")
	}
	cmdText := grubApplyCommand(t)

	out, err := run("sh", "-n", "-c", cmdText)
	if err != nil {
		t.Fatalf("the generated bootloader command is not valid shell: %v\n%s\n\n%s", err, out, cmdText)
	}
}

// grubby's output must reach the operator. It used to end in `>/dev/null 2>&1 || true`, so when
// fourteen cmdline controls failed to apply on rhel8, rhel10 and fedora, the failure could say only
// that the arguments were nowhere, never why (#382). The command that produced a failure must not
// be the one silencing it.
func TestGrubApplyKeepsTheReasonItFailed(t *testing.T) {
	cmdText := grubApplyCommand(t)

	if strings.Contains(cmdText, "grubby --update-kernel=ALL --args=\"") &&
		regexp.MustCompile(`grubby --update-kernel=ALL[^;]*>/dev/null 2>&1`).MatchString(cmdText) {
		t.Error("grubby's output is discarded again; a failure there can no longer explain itself")
	}
	for _, want := range []string{"grubby exited $__rc", "grub2-mkconfig exited $__mkrc"} {
		if !strings.Contains(cmdText, want) {
			t.Errorf("the failure message does not report %q", want)
		}
	}
}

// The failure path is the one that matters and the one nobody runs. This executes it: a shell where
// grubby and grub2-mkconfig are stubs that fail, and the command must exit non-zero AND carry both
// of their messages.
func TestGrubApplyFailurePathReportsBothCommands(t *testing.T) {
	if _, err := exec.LookPath("sh"); err != nil {
		t.Skip("no sh on this machine")
	}
	// Stubs on PATH, in a directory of our own: grubby says something recognisable and fails,
	// grub2-mkconfig likewise, and nothing writes the arguments anywhere.
	dir := t.TempDir()
	for name, msg := range map[string]string{
		"grubby":         "grubby: BLS entry is read-only",
		"grub2-mkconfig": "grub2-mkconfig: refusing to overwrite the wrapper",
	} {
		script := "#!/bin/sh\necho '" + msg + "' >&2\nexit 1\n"
		if err := writeExec(dir+"/"+name, script); err != nil {
			t.Fatal(err)
		}
	}
	// `grep` is stubbed to find nothing, and that is not a shortcut: the verification chain reads
	// absolute host paths, and THIS machine is itself hardened by pavois, so /etc/default/grub
	// carries `audit=1` and the command reported success. A test whose verdict depends on how the
	// machine running it is configured measures that machine, not the code.
	if err := writeExec(dir+"/grep", "#!/bin/sh\nexit 1\n"); err != nil {
		t.Fatal(err)
	}
	// update-grub must NOT exist, or the first branch wins and the grubby branch never runs.
	cmdText := grubApplyCommand(t)

	out, err := run("sh", "-c", "PATH="+dir+":/usr/bin:/bin; export PATH; "+cmdText)
	if err == nil {
		t.Fatalf("the command succeeded while nothing applied the arguments:\n%s", out)
	}
	for _, want := range []string{"Nothing applied them", "BLS entry is read-only", "grub2-mkconfig exited"} {
		if !strings.Contains(out, want) {
			t.Errorf("the failure does not mention %q. It said:\n%s", want, out)
		}
	}
	// grub2-mkconfig is called only when /boot/grub2/grub.cfg exists, so on a machine without one
	// the honest report is that it was skipped. Asserting its stub message unconditionally made
	// this test demand a call the code is right not to make.
	if !strings.Contains(out, "refusing to overwrite the wrapper") && !strings.Contains(out, "skipped") {
		t.Errorf("grub2-mkconfig is neither reported nor declared skipped. It said:\n%s", out)
	}
}

// grubApplyCommand renders a plan carrying one kernel-command-line remediation and returns the
// shell the recipe would run, unescaped.
func grubApplyCommand(t *testing.T) string {
	t.Helper()
	plan := loadPlan(t, `
target: pavois@host
os: rhel9
rules:
  cmdline-audit:
    apply: true
    status: gap
    remediation:
      resource: kernel_cmdline
      value: audit=1
`)
	recipe, _, _, _, _ := compileRecipe(plan, "", "", "", "")

	m := regexp.MustCompile(`(?s)execute 'pavois-grub-apply' do\s*\n\s*command (".*?")\n`).FindStringSubmatch(recipe)
	if m == nil {
		t.Fatalf("no pavois-grub-apply resource in the recipe:\n%s", recipe)
	}
	unquoted, err := strconv.Unquote(m[1])
	if err != nil {
		t.Fatalf("cannot unquote the command: %v", err)
	}
	return unquoted
}

func run(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).CombinedOutput()
	return string(out), err
}

func writeExec(path, content string) error {
	return exec.Command("sh", "-c", "cat > "+path+" <<'PAVOIS_STUB'\n"+content+"PAVOIS_STUB\nchmod 0755 "+path).Run()
}
