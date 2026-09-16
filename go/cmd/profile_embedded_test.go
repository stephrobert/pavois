package cmd

import (
	"path/filepath"
	"testing"

	"pavois/internal/corpus"
)

// A downloaded binary has no profiles/ on disk. It must still find the profile for the machine it
// is looking at, because the corpus is compiled into it.
//
// This is the defect that shipped in v0.1.0 and made the whole release useless. Every artifact
// installed cleanly, `pavois version` printed v0.1.0, and then:
//
//	error: no bundled profile for debian 12.15: pass --profile <path|url>
//
// The corpus WAS embedded: `ssh-disable-root-login` appears eleven times in the published binary.
// ResolveProfile even falls back to it correctly. But profileForPlatform decides WHICH profile to
// resolve, and it asked the filesystem: `os.Stat(root/profiles/linux/<p>)`. Outside a checkout that
// is always false, so no candidate was ever produced and the fallback was never reached.
//
// Nothing caught it because every test, every campaign and the preflight itself run from the
// repository, where profiles/ is on disk. The one thing nobody did was run the artifact somewhere
// else, which is the only place the bug exists.
func TestProfileForPlatformFindsEmbeddedCorpusWithoutDisk(t *testing.T) {
	if !corpus.Available() {
		t.Skip("no corpus embedded in this test binary (dev build): run `mise run render` first")
	}

	// An empty root: no profiles/ anywhere, exactly like /usr/bin/pavois on a fresh machine.
	root := t.TempDir()

	cases := []struct {
		name, release, want string
	}{
		{"debian", "12.15", "linux/debian12"},
		{"debian", "13.7", "linux/debian13"},
		{"ubuntu", "24.04", "linux/ubuntu2404"},
		{"almalinux", "9.4", "linux/rhel9"},
	}
	for _, c := range cases {
		profile, detected, why := profileForPlatform(root, c.name, c.release)
		if profile != c.want {
			t.Errorf("profileForPlatform(<empty root>, %q, %q) = %q, want %q (detected %q, why %q)",
				c.name, c.release, profile, c.want, detected, why)
		}
	}
}

// And the profile it names has to be resolvable, or the scan fails one step later with a different
// message. Naming a profile that cannot be extracted would turn one clear failure into two.
func TestResolvedEmbeddedProfileCarriesControls(t *testing.T) {
	if !corpus.Available() {
		t.Skip("no corpus embedded in this test binary (dev build): run `mise run render` first")
	}

	dest := t.TempDir()
	dir, ok := corpus.Extract(dest, "linux/debian12")
	if !ok {
		t.Fatal("linux/debian12 is embedded but Extract refused it")
	}
	matches, err := filepath.Glob(filepath.Join(dir, "controls", "*.rb"))
	if err != nil {
		t.Fatalf("glob: %v", err)
	}
	if len(matches) == 0 {
		t.Errorf("extracted %s carries no control file: a resolved profile with no rules scans nothing", dir)
	}
}
