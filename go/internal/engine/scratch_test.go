package engine

import (
	"fmt"
	"strings"
	"testing"
)

// Issue #288: a `--on-target` scan put the profile in /tmp and executed it there. Pavois then
// hardens the host, `mount-tmp-noexec` applies, and the next scan of that same host dies with
// `sh: 1: env: Permission denied` (exit 126). The tool had hardened a machine into a state where
// its own verification could not run.
//
// The probe is the fix, so these tests pin what it does rather than what it should find: a fake
// target answers for each candidate, and the choice is asserted.

// expanded is what a target actually prints back. The candidate list holds `$HOME/.pavois-run`,
// but the remote shell expands it before `printf` ever sees it, so the answer is an absolute path.
// The first version of this fake returned the candidate verbatim and modelled the wrong side of the
// exchange, which is how a test ends up asserting a shape the product never produces.
func expanded(cand string) string {
	return strings.Replace(cand, "$HOME", "/home/tester", 1)
}

// fakeTarget answers the probe as a machine would: a directory listed in `execOK` returns its own
// expanded path, everything else fails the way a noexec mount does, since the script is created,
// chmod'd, and then refused at exec time.
func fakeTarget(execOK ...string) func(string) (string, error) {
	ok := map[string]bool{}
	for _, d := range execOK {
		ok[d] = true
	}
	return func(remote string) (string, error) {
		for _, cand := range scratchCandidates {
			if !strings.Contains(remote, "d="+cand+";") {
				continue
			}
			if ok[cand] {
				return expanded(cand), nil
			}
			return "", fmt.Errorf("exit 126")
		}
		return "", fmt.Errorf("unexpected probe: %s", remote)
	}
}

func TestExecDirPrefersTheUsersOwnSpace(t *testing.T) {
	// Everything executable: it must still choose $HOME, which leaves no trace outside the
	// account being audited.
	got, err := execDirOnTarget(fakeTarget(scratchCandidates...), "")
	if err != nil {
		t.Fatalf("no directory chosen on a host where everything works: %v", err)
	}
	if got != "/home/tester/.pavois-run" {
		t.Errorf("chose %q, want the user's own space first", got)
	}
}

// The failure this exists for: /tmp is noexec, and the scan must carry on somewhere else instead of
// dying with exit 126.
func TestExecDirSkipsANoexecTmp(t *testing.T) {
	got, err := execDirOnTarget(fakeTarget("/var/tmp/pavois-run", "/opt/pavois-run"), "")
	if err != nil {
		t.Fatalf("gave up although /var/tmp could execute: %v", err)
	}
	if got != "/var/tmp/pavois-run" {
		t.Errorf("chose %q, want the first candidate that actually executes", got)
	}
}

// A fully hardened host: every candidate noexec. Giving up is correct; giving up SILENTLY, or with
// `exit 126: no report produced`, is what #288 is about. The message has to name the cause and the
// way out.
func TestExecDirExplainsItselfWhenNothingCanExecute(t *testing.T) {
	_, err := execDirOnTarget(fakeTarget(), "")
	if err == nil {
		t.Fatal("a host where nothing can execute returned a directory")
	}
	msg := err.Error()
	for _, want := range []string{"noexec", "mount-tmp-noexec", "--on-target"} {
		if !strings.Contains(msg, want) {
			t.Errorf("the error does not mention %q, so a reader cannot act on it:\n%s", want, msg)
		}
	}
	// And it must offer the way out, which is the transport that needs nothing executable there.
	if !strings.Contains(msg, "WITHOUT --on-target") {
		t.Errorf("the error does not offer the fallback:\n%s", msg)
	}
}

// The defect this fix shipped with, before the scenario caught it on a VM.
//
// The probe script PRINTS, and its "ok" landed on stdout right before the path. The caller got
// "ok\n/home/tester/.pavois-run" and handed scp a two-line destination, which the remote shell read
// as a command on line 1 and a path on line 2:
//
//	bash: line 2: /home/tester/.pavois-run/profile: No such file or directory
//
// A login banner, a chatty /etc/profile or a sudo lecture does the same thing. The answer is a path
// or it is nothing.
func TestExecDirIgnoresAnythingPrintedBeforeThePath(t *testing.T) {
	noisy := func(string) (string, error) {
		return "ok\nWelcome to Ubuntu 24.04.5 LTS\n/home/tester/.pavois-run\n", nil
	}
	got, err := execDirOnTarget(noisy, "")
	if err != nil {
		t.Fatalf("a chatty target defeated the probe: %v", err)
	}
	if got != "/home/tester/.pavois-run" {
		t.Errorf("chose %q; a banner or the probe's own output leaked into the path", got)
	}
}

// And a target that says only noise, with no path, is a target with no answer.
func TestExecDirRefusesAnAnswerThatIsNotAPath(t *testing.T) {
	_, err := execDirOnTarget(func(string) (string, error) { return "ok\n", nil }, "")
	if err == nil {
		t.Error("\"ok\" was accepted as a directory")
	}
}

// `test -x` would pass on a noexec mount: the bit is set, the kernel refuses at exec time. The
// probe must actually run the file, or it measures the wrong thing.
func TestExecDirProbeRunsTheFileRatherThanTestingTheBit(t *testing.T) {
	var seen string
	_, _ = execDirOnTarget(func(remote string) (string, error) {
		if seen == "" {
			seen = remote
		}
		return "", fmt.Errorf("no")
	}, "")
	if strings.Contains(seen, "test -x") {
		t.Errorf("the probe tests the executable bit, which is set on a noexec mount:\n%s", seen)
	}
	if !strings.Contains(seen, ".probe") || !strings.Contains(seen, "chmod") {
		t.Errorf("the probe does not create and run a file:\n%s", seen)
	}
}
