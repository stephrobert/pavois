package corpus

import (
	"os"
	"path/filepath"
	"testing"
)

func TestExtractMissing(t *testing.T) {
	if _, ok := Extract(t.TempDir(), "linux/does-not-exist"); ok {
		t.Error("Extract should fail for a non-embedded profile")
	}
}

func TestExtractWhenAvailable(t *testing.T) {
	if !Available() {
		t.Skip("no corpus embedded in this build (dev build); release build embeds it")
	}
	dir, ok := Extract(t.TempDir(), "linux/debian12")
	if !ok {
		t.Fatal("debian12 should extract when a corpus is embedded")
	}
	rb, _ := filepath.Glob(filepath.Join(dir, "controls", "*.rb"))
	if len(rb) == 0 {
		t.Errorf("extracted profile has no .rb under %s", dir)
	}
	_ = os.RemoveAll(dir)
}
