package cmd

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/stephrobert/scankit/assessment"

	"pavois/internal/audit"
)

// provenance.go stamps the run-level envelope that makes an assessment opposable: WHO produced
// it (pavois version + binary digest), against WHAT ruleset (name + version + content digest),
// on WHICH target, WHEN, from which source, and over what scope. Without it a per-control
// result is not reproducible. The tool/ruleset digests are the non-repudiation anchor — the
// same ruleset content digest also lands in the evidence bundle's manifest (see bundle.go).

// binaryDigest returns "sha256:<hex>" of the running pavois binary, or "" if it can't be read.
func binaryDigest() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	s, _, err := sha256File(exe)
	if err != nil {
		return ""
	}
	return "sha256:" + s
}

// rulesetDigest is a deterministic content hash of the evaluated profile — the corpus of
// InSpec controls actually run. It closes the gap the brief flags: the bundle manifest carried
// a ruleset VERSION string but no content hash, so two different rulesets could share a
// version. profile is the value passed to `scan --profile` (e.g. "linux/debian12", a path, or a
// URL); root is the repo root. Returns "sha256:<hex>" or "" when the profile is not a local dir
// (a URL) or is unreadable.
func rulesetDigest(root, profile string) string {
	dir := ""
	for _, cand := range []string{
		filepath.Join(root, "profiles", profile), // bundled name: profiles/linux/debian12
		profile,                                  // an explicit path
	} {
		if fi, err := os.Stat(cand); err == nil && fi.IsDir() {
			dir = cand
			break
		}
	}
	if dir == "" {
		return ""
	}
	return dirDigest(dir)
}

// dirDigest hashes every regular file under dir (relative path + content, in sorted order) into
// one SHA-256. Stable across runs and machines, so it identifies the ruleset by its content.
func dirDigest(dir string) string {
	type entry struct{ rel, abs string }
	var files []entry
	err := filepath.WalkDir(dir, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(dir, p)
		if err != nil {
			return err
		}
		files = append(files, entry{rel: filepath.ToSlash(rel), abs: p})
		return nil
	})
	if err != nil {
		return ""
	}
	sort.Slice(files, func(i, j int) bool { return files[i].rel < files[j].rel })
	h := sha256.New()
	for _, f := range files {
		b, err := os.ReadFile(f.abs) //nolint:gosec // repo-local profile corpus, read-only
		if err != nil {
			return ""
		}
		h.Write([]byte(f.rel))
		h.Write([]byte{0})
		h.Write(b)
		h.Write([]byte{0})
	}
	return "sha256:" + hex.EncodeToString(h.Sum(nil))
}

// scanProvenance builds the assessment.Run for a scan: tool and ruleset identity with content
// digests, the target, an RFC3339 UTC timestamp, the source (transport, or "export" for a
// report replayed with --from) and the evaluated scope.
func scanProvenance(root, profile, transport, subject string, rep *audit.Report, standard, level string, exported bool, now time.Time) assessment.Run {
	rulesetVer := ""
	if len(rep.Profiles) > 0 {
		rulesetVer = rep.Profiles[0].Version
	}
	source := strings.TrimSuffix(transport, "://") // ssh | local | docker
	if exported {
		source = "export"
	}
	return assessment.Run{
		Tool: assessment.Component{Name: "pavois", Version: version, Digest: binaryDigest()},
		Ruleset: assessment.Component{
			Name: "pavois-baseline", Version: rulesetVer, Digest: rulesetDigest(root, profile),
		},
		Target: assessment.Target{
			ID:       subject,
			Platform: strings.TrimSpace(rep.Platform.Name + " " + rep.Platform.Release),
		},
		Timestamp: now.UTC().Format(time.RFC3339),
		Source:    source,
		Scope:     scopeOf(standard, level),
	}
}

// scopeOf attests which standards and level were evaluated — the coverage an auditor must be
// able to trust. An empty standard means every mapped standard was in scope.
func scopeOf(standard, level string) assessment.Scope {
	sc := assessment.Scope{}
	if standard == "" || standard == "all" {
		sc.Included = append([]string(nil), audit.Standards()...)
	} else {
		sc.Included = []string{standard}
	}
	if level != "" && level != "all" {
		sc.Note = "level " + level
	}
	return sc
}
