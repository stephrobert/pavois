package cmd

import (
	"bytes"
	"strings"
	"testing"
)

func TestVersionFlags(t *testing.T) {
	for _, flag := range []string{"--version", "-v"} {
		t.Run(flag, func(t *testing.T) {
			buf := new(bytes.Buffer)
			rootCmd.SetOut(buf)
			rootCmd.SetErr(buf)
			rootCmd.SetArgs([]string{flag})

			err := rootCmd.Execute()
			if err != nil {
				t.Fatalf("unexpected error for %s: %v", flag, err)
			}

			out := strings.TrimSpace(buf.String())
			expected := "Pavois " + version
			if out != expected {
				t.Errorf("got %q, want %q", out, expected)
			}
		})
	}
}
