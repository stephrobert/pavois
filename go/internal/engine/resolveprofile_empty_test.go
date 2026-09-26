package engine

import (
	"os"
	"path/filepath"
	"testing"

	"pavois/internal/corpus"
)

// An EMPTY profile directory must never win over a corpus the binary is carrying.
//
// # THE DEFECT THIS PINS DOWN
//
// profiles/linux/<os>/inspec.yml and waivers.yml are tracked; controls/*.rb are produced by
// `mise run render` and gitignored. So in a fresh checkout the directory exists, looks exactly like
// a profile, and holds nothing to evaluate. ResolveProfile returned it on sight.
//
// The nightly campaign runs the RELEASED binary from a checkout, and that is where it showed:
//
//	pavois: detected debian 12.15 -> profile linux/debian12
//	error: the scan evaluated 0 controls, so there is nothing to grade
//	  if it is a bundled profile, the corpus may not be rendered yet: run `mise run regen`
//
// The tool refused to grade, which is right, and it refused while carrying the rules it needed.
// For a compliance scanner that is the worst shape of bug: the answer was in hand and the answer
// given was "I have none". Nothing caught it because a checkout normally has the corpus rendered,
// and a machine without a checkout has no empty directory to trip over. Only the two together fail.
func TestEmptyProfileDirectoryDoesNotShadowTheEmbeddedCorpus(t *testing.T) {
	if !corpus.Available() {
		t.Skip("no corpus embedded in this test binary (dev build): run `mise run render` first")
	}

	root := t.TempDir()
	// A checkout as git leaves it: the profile's metadata, and no controls beside it.
	dir := filepath.Join(root, "profiles", "linux", "debian12")
	if err := os.MkdirAll(filepath.Join(dir, "controls"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "inspec.yml"), []byte("name: debian12\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := ResolveProfile(root, "linux/debian12")
	if err != nil {
		t.Fatalf("ResolveProfile returned an error while the profile was embedded: %v", err)
	}
	if got == dir {
		t.Fatalf("ResolveProfile chose the empty checkout directory %q over the embedded corpus", got)
	}
	if !hasControls(got) {
		t.Fatalf("ResolveProfile returned %q, which has no controls either", got)
	}
}

// The other direction, which matters just as much: a checkout WITH a rendered corpus must keep
// winning. A developer editing rules.yml and rendering has to be scanning their own rules, not the
// ones frozen into the binary when it was built.
func TestRenderedCheckoutStillWinsOverTheEmbeddedCorpus(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "profiles", "linux", "debian12")
	if err := os.MkdirAll(filepath.Join(dir, "controls"), 0o755); err != nil {
		t.Fatal(err)
	}
	rb := filepath.Join(dir, "controls", "ssh.rb")
	if err := os.WriteFile(rb, []byte("control 'x' do\nend\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := ResolveProfile(root, "linux/debian12")
	if err != nil {
		t.Fatal(err)
	}
	if got != dir {
		t.Fatalf("ResolveProfile(%q) = %q, want the rendered checkout directory", dir, got)
	}
}

// A profile that is NOT embedded is returned as it always was, empty or not: falling back is only
// possible when there is something to fall back to, and inventing an error here would break anyone
// pointing at a profile of their own.
func TestUnembeddedEmptyProfileIsStillReturned(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "profiles", "linux", "no-such-distro-9")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := ResolveProfile(root, "linux/no-such-distro-9")
	if err != nil {
		t.Fatal(err)
	}
	if got != dir {
		t.Fatalf("ResolveProfile = %q, want %q", got, dir)
	}
}

func TestHasControls(t *testing.T) {
	base := t.TempDir()
	cases := []struct {
		name  string
		files []string
		want  bool
	}{
		{"a rendered profile", []string{"controls/ssh.rb"}, true},
		{"several controls", []string{"controls/ssh.rb", "controls/audit.rb"}, true},
		{"metadata but no controls", []string{"inspec.yml"}, false},
		{"an empty controls directory", []string{"controls/"}, false},
		{"something that is not a control", []string{"controls/README.md"}, false},
		{"nothing at all", nil, false},
	}
	for i, c := range cases {
		dir := filepath.Join(base, string(rune('a'+i)))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		for _, f := range c.files {
			p := filepath.Join(dir, f)
			if filepath.Base(f) == "" || f[len(f)-1] == '/' {
				if err := os.MkdirAll(p, 0o755); err != nil {
					t.Fatal(err)
				}
				continue
			}
			if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(p, []byte("x"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		if got := hasControls(dir); got != c.want {
			t.Errorf("hasControls(%s) = %v, want %v", c.name, got, c.want)
		}
	}
}
