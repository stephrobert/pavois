package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// TestDirDigestDeterministic: the ruleset content digest is stable across calls and identifies
// the corpus by content — a byte change flips it, file order does not.
func TestDirDigestDeterministic(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.rb"), []byte("control 'x'"), 0o600); err != nil {
		t.Fatal(err)
	}
	sub := filepath.Join(dir, "controls")
	if err := os.MkdirAll(sub, 0o750); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(sub, "b.rb"), []byte("control 'y'"), 0o600); err != nil {
		t.Fatal(err)
	}

	d1 := dirDigest(dir)
	d2 := dirDigest(dir)
	if d1 == "" || d1 != d2 {
		t.Fatalf("digest not deterministic: %q vs %q", d1, d2)
	}
	// A content change must flip the digest.
	if err := os.WriteFile(filepath.Join(sub, "b.rb"), []byte("control 'z'"), 0o600); err != nil {
		t.Fatal(err)
	}
	if dirDigest(dir) == d1 {
		t.Errorf("digest unchanged after a content edit")
	}
	// A missing directory yields no digest, not a panic.
	if got := dirDigest(filepath.Join(dir, "does-not-exist")); got != "" {
		t.Errorf("digest of missing dir = %q, want empty", got)
	}
}

// TestScopeOf: an empty standard attests every mapped standard; a specific one narrows it, and
// the level is noted.
func TestScopeOf(t *testing.T) {
	if sc := scopeOf("", ""); len(sc.Included) != 5 || sc.Note != "" {
		t.Errorf("scopeOf(all) = %+v", sc)
	}
	sc := scopeOf("cis", "1")
	if len(sc.Included) != 1 || sc.Included[0] != "cis" || sc.Note != "level 1" {
		t.Errorf("scopeOf(cis,1) = %+v", sc)
	}
}
