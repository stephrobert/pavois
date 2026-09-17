package engine

import (
	"fmt"
	"strings"
	"testing"
)

// #288, after the diagnosis was corrected twice.
//
// The first reading blamed `mount-tmp-noexec` and a working directory. The second blamed pavois's
// `sudo sh -c` elevation. Both were wrong, and the measurement said so: under a global
// `Defaults noexec`, cinc-auditor is blocked inside mixlib-shellout on its FIRST control, with or
// without a package-manager carve-out, because auditing effective configuration means executing
// commands. The same scan runs with noexec off, which is the control group that makes that mean
// something.
//
// So pavois cannot work around it and must not pretend to. What it owes the reader is a sentence
// instead of `exit 126: no report produced`.

func TestSudoForbidsExecSeesAGlobalDefault(t *testing.T) {
	yes := func(string) (string, error) { return "1\n", nil }
	if !sudoForbidsExec(yes) {
		t.Error("a global Defaults noexec went unnoticed")
	}
}

func TestSudoForbidsExecIgnoresAScopedOne(t *testing.T) {
	// `Defaults!/usr/bin/vi noexec` hardens one command and leaves the engine alone. Counting it
	// would refuse to scan a host that scans perfectly well.
	no := func(string) (string, error) { return "0\n", nil }
	if sudoForbidsExec(no) {
		t.Error("a scoped noexec was taken for a global one")
	}
}

// A probe that cannot run tells us nothing, and "nothing" must never become an accusation: a target
// that refuses the grep (no sudo, no such file, a closed connection) is not a target with noexec.
func TestSudoForbidsExecNeverAccusesOnAFailedProbe(t *testing.T) {
	broken := func(string) (string, error) { return "", fmt.Errorf("connection closed") }
	if sudoForbidsExec(broken) {
		t.Error("a failed probe was read as a positive finding")
	}
	empty := func(string) (string, error) { return "", nil }
	if sudoForbidsExec(empty) {
		t.Error("an empty answer was read as a positive finding")
	}
}

// The message is the whole deliverable here, since the condition cannot be worked around. It has to
// name the cause, the control, and both ways out.
func TestNoexecErrorNamesTheCauseAndTheWayOut(t *testing.T) {
	msg := noexecError("pavois@10.0.0.2").Error()
	// Case-insensitive on purpose: what matters is that the idea is present, not its capitalisation.
	lower := strings.ToLower(msg)
	for _, want := range []string{
		"defaults noexec", // the cause, by its exact spelling in sudoers
		"sudo-noexec",     // the control responsible, so it can be looked up
		"root@10.0.0.2",   // the first way out: a session where noexec does not apply
		"--on-target",     // the second: run the engine here instead of there
		"effective",       // why it cannot simply be worked around
	} {
		if !strings.Contains(lower, want) {
			t.Errorf("the message does not mention %q:\n%s", want, msg)
		}
	}
	// And it must not offer a fix that does not exist. Earlier drafts of this suggested choosing a
	// different working directory, which no amount of choosing would have helped.
	if strings.Contains(msg, "TMPDIR") || strings.Contains(msg, "writable") {
		t.Errorf("the message still offers a directory fix, which cannot work:\n%s", msg)
	}
}
