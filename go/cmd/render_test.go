package cmd

import (
	"bytes"
	"strings"
	"testing"
)

func TestRenderToStdout(t *testing.T) {
	dir := t.TempDir()
	rep := writeReport(t, dir, "rep.json",
		ctrl("c-pass", "passed"),
		ctrl("c-fail", "failed"),
	)

	var out bytes.Buffer
	renderCmd.SetOut(&out)
	renderOut, renderMachine, renderTimestamp = "", "203.0.113.10", "2026-01-01 00:00:00 UTC"
	if err := runRender(renderCmd, []string{rep}); err != nil {
		t.Fatal(err)
	}
	got := out.String()
	if !strings.Contains(got, "<!doctype html>") && !strings.Contains(got, "<!DOCTYPE html>") {
		t.Errorf("render output is not HTML:\n%s", got[:min(200, len(got))])
	}
	for _, want := range []string{"c-pass", "c-fail", "203.0.113.10"} {
		if !strings.Contains(got, want) {
			t.Errorf("render output missing %q", want)
		}
	}
}
