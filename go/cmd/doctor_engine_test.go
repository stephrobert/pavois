package cmd

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// plantEngine puts a fake cinc-auditor first on PATH and returns nothing: the test's whole subject
// is what doctor does with it.
func plantEngine(t *testing.T, script string) {
	t.Helper()
	d := t.TempDir()
	p := filepath.Join(d, "cinc-auditor")
	if err := os.WriteFile(p, []byte(script), 0o700); err != nil { //nolint:gosec // a fake binary in a temp dir
		t.Fatalf("plant: %v", err)
	}
	t.Setenv("PATH", d+string(os.PathListSeparator)+os.Getenv("PATH"))
}

// A package built for another libc installs perfectly: the file is there, it is executable, the
// checksum was right, and it cannot start. doctor used to stop at LookPath and answer
// "ready: try: pavois scan local --sudo" on exactly that machine. Measured on a debian 12 VM given
// the Ubuntu package: doctor said ready, and every step after it ran against nothing.
func TestDoctorRefusesAnEngineThatCannotRun(t *testing.T) {
	plantEngine(t, "#!/bin/sh\n"+
		"echo \"/opt/cinc-auditor/embedded/bin/ruby: libc.so.6: version \\`GLIBC_2.38' not found\" >&2\n"+
		"exit 1\n")

	var buf bytes.Buffer
	doctorCmd.SetOut(&buf)
	doctorCmd.SetErr(&buf)
	err := runDoctor(doctorCmd, nil)
	got := buf.String()

	if err == nil {
		t.Fatal("doctor accepted a host whose engine cannot run")
	}
	for _, want := range []string{
		"installed but cannot run", // it names the real problem
		"GLIBC_2.38",               // and quotes what the engine actually said
	} {
		if !strings.Contains(got, want) {
			t.Errorf("the report does not contain %q:\n%s", want, got)
		}
	}
	// The closing advice must never be "install a scan engine": that sends the reader to do the
	// thing they already did, and it is the defect this file warns about for the missing-asset
	// case too.
	if strings.Contains(err.Error(), "install a scan engine") {
		t.Errorf("the advice tells them to install an engine that IS installed: %v", err)
	}
	// Which advice it IS depends on the environment, and asserting the engine one unconditionally
	// is what made this test pass here and fail in CI. A bare checkout has no rendered corpus, so
	// the missing-asset error comes first, and that ORDER is deliberate: a binary carrying no
	// reference is unusable whatever the engine does. So the engine advice is demanded only when
	// nothing more fundamental is wrong, and the report line above carries the contract that holds
	// in both environments.
	if !strings.Contains(got, "[FAIL] hardening reference") && !strings.Contains(err.Error(), "built without") {
		if !strings.Contains(err.Error(), "cannot run on this system") {
			t.Errorf("the advice does not say what is wrong: %v", err)
		}
	}
	if strings.Contains(got, "ready: try:") {
		t.Error("doctor still declared the host ready")
	}
}

// The other direction, without which an over-strict check would look perfect: an engine that
// answers must still be reported OK, and doctor must not turn its own probe into a failure.
func TestDoctorAcceptsAnEngineThatAnswers(t *testing.T) {
	plantEngine(t, "#!/bin/sh\necho 'Cinc Auditor version: 7.1.7'\nexit 0\n")

	var buf bytes.Buffer
	doctorCmd.SetOut(&buf)
	doctorCmd.SetErr(&buf)
	_ = runDoctor(doctorCmd, nil) // other prerequisites may be missing on a CI box; the line is the subject
	got := buf.String()

	if !strings.Contains(got, "[OK  ] CINC engine (native)") {
		t.Errorf("a working engine was not reported OK:\n%s", got)
	}
	if strings.Contains(got, "cannot run") {
		t.Errorf("a working engine was reported as broken:\n%s", got)
	}
}
