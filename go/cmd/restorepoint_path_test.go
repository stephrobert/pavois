package cmd

import (
	"strings"
	"testing"
)

// The restore point must not be staged in /tmp, because pavois hardens /tmp.
//
// # THE DEFECT THIS PINS DOWN
//
// Pass 1 of a campaign sets fs.protected_regular = 2 and chowns the archive to the connecting
// account. Pass 2 then arrives as root, finds a file it does not own inside a sticky world-writable
// directory, and is refused:
//
//	tar (child): /tmp/pavois-restore-point.tar.gz: Cannot open: Permission denied
//	error: restore point: capture prior state: exit status 1
//
// `harden apply` stops there, before converging anything. Every RHEL campaign has therefore been
// running one pass instead of two, and the three controls it reported as regressions had been
// planned, armed and rendered without ever being executed. The correlation over nine platforms was
// exact: the three that failed the restore point are the three that reported regressions (#380).
func TestRestorePointIsNotStagedInTmp(t *testing.T) {
	rp := restorePoint{
		Files:    []rpFile{{Path: "/etc/at.deny"}},
		Packages: []rpPkg{{Name: "at", Action: "install"}},
		Services: []rpSvc{{Name: "atd"}},
	}
	capture := captureScript(rp)

	if strings.Contains(capture, "/tmp/") {
		t.Errorf("the capture script still stages in /tmp:\n%s", firstLineWith(capture, "/tmp/"))
	}
	// The mode is set, not inherited. Relying on the umask produced a directory the connecting
	// account could not traverse, so the capture passed and the fetch that follows it died with
	// "scp: /var/lib/pavois/restore-point.tar.gz: Permission denied". The failure had moved one
	// step later, which is not the same as being fixed.
	if !strings.Contains(capture, "chmod 0755 "+targetStateDir) {
		t.Errorf("the capture script leaves %s at whatever the umask gives it:\n%s",
			targetStateDir, firstLineWith(capture, "mkdir -p "+targetStateDir))
	}

	for _, want := range []string{targetRPDir, targetRPTar} {
		if !strings.Contains(capture, want) {
			t.Errorf("the capture script never mentions %q", want)
		}
		if !strings.HasPrefix(want, "/var/lib/") {
			t.Errorf("%q is not under /var/lib, where no control in this corpus reaches", want)
		}
	}
}

// restoreScript is a RAW string literal, so Go concatenation inside it is not concatenation: it is
// those characters, in the shell script. A textual edit put `" + targetRPDir + "` into it, the
// build stayed green, and every rollback would have died on `cd " + targetRPDir + "`. The
// placeholder is substituted at the call site, and this checks the substitution actually happens.
func TestRestoreScriptHasNoUnsubstitutedPlaceholderOrGoSyntax(t *testing.T) {
	// What the caller builds, reproduced here rather than reimplemented: the same expression.
	script := strings.ReplaceAll(restoreScript, "@RPDIR@", targetRPDir)

	if strings.Contains(script, "@RPDIR@") {
		t.Error("a placeholder survived into the shell script")
	}
	for _, leak := range []string{`" + target`, `" +`, "targetRPDir"} {
		if strings.Contains(script, leak) {
			t.Errorf("Go syntax leaked into the shell script: %q in\n%s", leak, firstLineWith(script, leak))
		}
	}
	if !strings.Contains(script, "cd "+targetRPDir+" ") {
		t.Errorf("the script does not cd into the restore point directory:\n%s", firstLineWith(script, "cd "))
	}
	if strings.Contains(script, "/tmp/pavois") {
		t.Errorf("the restore script still refers to /tmp:\n%s", firstLineWith(script, "/tmp/pavois"))
	}
}

// The raw literal itself must keep its placeholder. Without this, someone "helpfully" replacing
// @RPDIR@ with a hardcoded path would silently undo the substitution and both tests above would
// still pass.
func TestRestoreScriptStillUsesThePlaceholder(t *testing.T) {
	if !strings.Contains(restoreScript, "@RPDIR@") {
		t.Error("restoreScript no longer carries @RPDIR@: the call-site substitution is now a no-op")
	}
}

func firstLineWith(s, needle string) string {
	for _, line := range strings.Split(s, "\n") {
		if strings.Contains(line, needle) {
			return "    " + line
		}
	}
	return "    (not found)"
}
