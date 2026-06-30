package cmd

import (
	"bytes"
	"strings"
	"testing"
)

func TestDoctor(t *testing.T) {
	var b bytes.Buffer
	doctorCmd.SetOut(&b)
	// May return an error if neither cinc-auditor nor docker is present (e.g. CI); we only
	// assert it runs and reports each prerequisite, not the readiness verdict.
	_ = runDoctor(doctorCmd, nil)
	s := b.String()
	for _, w := range []string{"CINC engine", "rule corpus", "sudo", "ssh"} {
		if !strings.Contains(s, w) {
			t.Errorf("doctor output missing %q\n---\n%s", w, s)
		}
	}
}
