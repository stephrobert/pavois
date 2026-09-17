package cmd

import (
	"strings"
	"testing"

	"pavois/internal/reference"
)

// Issue #286: `harden plan` could not run from a downloaded binary.
//
// The reference was read with os.ReadFile under findRoot(), and findRoot() falls back to the
// CURRENT DIRECTORY when it finds no profiles/ above it, which is always the case outside a
// checkout. So the path moved when you cd'd, which is what the reporter observed:
//
//	/root/docs/reference/pavois-content/ubuntu2404.yml     (from /root)
//	/opt/essai/docs/reference/pavois-content/ubuntu2404.yml (from /opt/essai)
//
// These tests run with an EMPTY root, which is what a downloaded binary has. They were written
// before the fix and failed against it, the same way go/cmd/profile_embedded_test.go did for the
// rule corpus: the bug they describe is not hypothetical, it shipped in v0.1.1.
//
// They skip on a dev build, where the embed dir holds only .keep. `mise run embed:reference`
// populates it, and the release workflow does the same before `go build`.

func TestReadReferenceFindsEmbeddedWithoutDisk(t *testing.T) {
	if !reference.Available() {
		t.Skip("no embedded reference in this build (mise run embed:reference)")
	}
	empty := t.TempDir() // no docs/ anywhere: a downloaded binary's world

	for _, osName := range reference.Names() {
		b, err := readReference(empty, osName)
		if err != nil {
			t.Errorf("readReference(%q) from an empty root: %v", osName, err)
			continue
		}
		if len(b) == 0 {
			t.Errorf("readReference(%q) returned an empty document", osName)
		}
		// Not just any bytes: the document has to carry the rules the plan is built from.
		if !strings.Contains(string(b), "rules:") {
			t.Errorf("readReference(%q) returned a document with no rules: block", osName)
		}
	}
}

func TestReferenceOSesSeesEmbeddedWithoutDisk(t *testing.T) {
	if !reference.Available() {
		t.Skip("no embedded reference in this build (mise run embed:reference)")
	}
	got := referenceOSes(t.TempDir())
	if len(got) < 5 {
		t.Fatalf("referenceOSes from an empty root = %v, want every embedded system", got)
	}
	// `norms` and `oscal` walk this list. An empty one is not an error there, it is a silently
	// empty catalogue, which is worse: the command succeeds and reports nothing.
	for _, want := range []string{"debian12", "ubuntu2404", "rhel9"} {
		if !contains(got, want) {
			t.Errorf("referenceOSes() = %v, missing %q", got, want)
		}
	}
}

// A missing system must say what IS available. The old error named an internal repository path
// that no user could create, which is the part that made the failure a dead end.
func TestReadReferenceUnknownOSNamesWhatExists(t *testing.T) {
	if !reference.Available() {
		t.Skip("no embedded reference in this build (mise run embed:reference)")
	}
	_, err := readReference(t.TempDir(), "plan9")
	if err == nil {
		t.Fatal("readReference(\"plan9\") succeeded, want an error")
	}
	if !strings.Contains(err.Error(), "known systems are") {
		t.Errorf("error does not list the known systems: %v", err)
	}
	if strings.Contains(err.Error(), "docs/reference/pavois-content") {
		t.Errorf("error still names an internal repository path: %v", err)
	}
}

func contains(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
