// Package corpus embeds the rendered InSpec rule corpus so a released, standalone pavois
// binary can scan without the repository on disk. A dev build embeds an empty corpus (only
// .keep) and falls back to the on-disk profiles/; a release build runs `mise run render`
// which copies profiles/ into this package before `go build`, so the binary is self-contained.
package corpus

import (
	"embed"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

//go:embed all:profiles
var fsys embed.FS

// Available reports whether a non-empty corpus is embedded (a release build).
func Available() bool {
	n := 0
	_ = fs.WalkDir(fsys, "profiles", func(_ string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() && strings.HasSuffix(d.Name(), ".rb") {
			n++
		}
		return nil
	})
	return n > 0
}

// Has reports whether profile <p> (e.g. "linux/debian12") is embedded.
//
// Callers used to answer this with os.Stat under the repository's profiles/, which is correct in a
// checkout and always false for a downloaded binary. That is how a release shipped with the corpus
// compiled in and no way to find it.
func Has(p string) bool {
	fi, err := fs.Stat(fsys, filepath.Join("profiles", p))
	return err == nil && fi.IsDir()
}

// Names lists the embedded profiles under "linux/", without extracting anything. Used to pick the
// closest profile of a family when no exact match exists.
func Names() []string {
	entries, err := fs.ReadDir(fsys, filepath.Join("profiles", "linux"))
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() {
			out = append(out, e.Name())
		}
	}
	return out
}

// Title reads a profile's inspec.yml title straight from the embedded filesystem, so the listing
// command can describe an embedded profile without extracting it to disk first.
func Title(p string) string {
	b, err := fs.ReadFile(fsys, filepath.Join("profiles", p, "inspec.yml"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(b), "\n") {
		if rest, ok := strings.CutPrefix(strings.TrimSpace(line), "title:"); ok {
			return strings.Trim(strings.TrimSpace(rest), `"'`)
		}
	}
	return ""
}

// Extract writes the embedded profile <p> (e.g. "linux/debian12") to <dest>/<p> and returns the
// directory, or ("", false) if that profile is not embedded. Used by ResolveProfile as a fallback
// when profiles/ is not on disk (a downloaded binary).
func Extract(dest, p string) (string, bool) {
	src := filepath.Join("profiles", p)
	if fi, err := fs.Stat(fsys, src); err != nil || !fi.IsDir() {
		return "", false
	}
	out := filepath.Join(dest, p)
	err := fs.WalkDir(fsys, src, func(path string, d fs.DirEntry, werr error) error {
		if werr != nil {
			return werr
		}
		rel, _ := filepath.Rel(src, path)
		target := filepath.Join(out, rel)
		if d.IsDir() {
			return os.MkdirAll(target, 0o755) //nolint:gosec // extracted corpus, world-readable by design
		}
		b, e := fsys.ReadFile(path)
		if e != nil {
			return e
		}
		return os.WriteFile(target, b, 0o644) //nolint:gosec // rule files are not secret
	})
	if err != nil {
		return "", false
	}
	return out, true
}
