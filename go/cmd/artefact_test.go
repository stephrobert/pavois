package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// A generated file that differs from its committed copy by one byte is rewritten on every run, so
// `git status` is permanently dirty after a site build and every tool that asks "did anything
// drift?" answers yes. tools/validate_prs.sh reported exactly that about two files that had not
// drifted at all, which is how a warning stops being read.
func TestWriteArtefactAlwaysEndsWithANewline(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"no trailing newline, the case that caused this", "</html>", "</html>\n"},
		{"already has one, left alone", "}\n", "}\n"},
		{"empty", "", "\n"},
		{"several, only the last matters", "a\n\n", "a\n\n"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			p := filepath.Join(t.TempDir(), "out")
			if err := writeArtefact(p, []byte(c.in)); err != nil {
				t.Fatalf("writeArtefact: %v", err)
			}
			got, err := os.ReadFile(p) //nolint:gosec // a path this test just created
			if err != nil {
				t.Fatalf("read back: %v", err)
			}
			if string(got) != c.want {
				t.Errorf("wrote %q, want %q", got, c.want)
			}
		})
	}
}

// Writing the same content twice must produce the same bytes. Without it, "the file changed" stops
// meaning "the content changed", and that is the whole value of a generated tree under version
// control.
func TestWriteArtefactIsIdempotent(t *testing.T) {
	p := filepath.Join(t.TempDir(), "out")
	const body = `{"grade":"B"}`
	for i := range 2 {
		if err := writeArtefact(p, []byte(body)); err != nil {
			t.Fatalf("pass %d: %v", i, err)
		}
	}
	got, err := os.ReadFile(p) //nolint:gosec // a path this test just created
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != body+"\n" {
		t.Errorf("after two passes: %q, want %q", got, body+"\n")
	}
}
