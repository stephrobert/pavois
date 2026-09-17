package cmd

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/stephrobert/scankit/assessment"

	"pavois/internal/audit"
	"pavois/internal/corpus"
)

// provenance.go stamps the run-level envelope that makes an assessment opposable: WHO produced
// it (pavois version + binary digest), against WHAT ruleset (name + version + content digest),
// on WHICH target, WHEN, from which source, and over what scope. Without it a per-control
// result is not reproducible. The tool/ruleset digests are the non-repudiation anchor, the
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

// rulesetDigest is a deterministic content hash of the evaluated profile, the corpus of
// InSpec controls actually run. The bundle manifest carried a ruleset VERSION string and no
// content hash, so two different rulesets could share a version. profile is the value passed to
// `scan --profile` (e.g. "linux/debian12", a path, or a URL); root is the repo root.
//
// It used to ask the filesystem and nothing else, so a downloaded binary wrote the field as an
// empty string, with no error, into an artifact whose entire purpose is to stay interpretable
// after the fact (#296). An evidence bundle is read months later, by someone else; a blank
// identity is discovered at the one moment it cannot be recovered.
//
// The embedded corpus is byte-for-byte the rendered profiles/, so extracting it yields the same
// digest a checkout does. That equality is the reason a release bundle and a source bundle remain
// comparable, and it is asserted by tools/release/same_outside_checkout.sh rather than assumed.
//
// Returns "sha256:<hex>", or "" only when the profile genuinely has no local content to hash (a
// URL). Callers must NOT write "" into a manifest as if it were a digest: see bundle.go.
func rulesetDigest(root, profile string) string {
	for _, cand := range []string{
		filepath.Join(root, "profiles", profile), // bundled name: profiles/linux/debian12
		profile,                                  // an explicit path
	} {
		if fi, err := os.Stat(cand); err == nil && fi.IsDir() {
			return dirDigest(cand)
		}
	}
	// Nothing on disk: a released binary. Extract the embedded copy and hash that.
	if dest, ok := corpus.Extract(filepath.Join(os.TempDir(),
		fmt.Sprintf("pavois-digest-%d", os.Getuid())), profile); ok {
		return dirDigest(dest)
	}
	return ""
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

// scopeOf attests which standards and level were evaluated, the coverage an auditor must be
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
