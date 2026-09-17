// Package reference embeds the per-OS hardening reference (docs/reference/pavois-content/<os>.yml)
// so a released, standalone pavois binary can plan a remediation, list rules, report norm coverage
// and emit OSCAL without the repository on disk.
//
// This exists because of issue #286. The rule corpus was embedded and the reference was not, so a
// downloaded binary could SCAN a host and then failed the moment it tried to do anything with the
// remediation knowledge:
//
//	pavois harden plan local
//	error: read reference: open /root/docs/reference/pavois-content/ubuntu2404.yml: no such file
//
// The path moved with the current directory, which is the tell: it was resolved against the cwd.
// Half the product was unreachable for anyone who installed from a release, and the error named an
// internal repository path rather than anything the user could act on.
//
// Same shape as internal/corpus: a dev build embeds only .keep and the commands fall back to the
// on-disk reference; a release build runs `mise run embed:reference` before `go build`.
package reference

import (
	"embed"
	"io/fs"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed all:content
var fsys embed.FS

// The norm catalogue, in its own directory because it is not a system: putting norms.yml beside
// the per-OS files would make `norms` appear in the list of supported systems. It is small (a few
// kilobytes) and it was missed on the first pass: `pavois norms` failed with
// `read norm catalogue: open /tmp/docs/reference/norms.yml`, found by the VM scenario and not by
// any test running inside the repository.
//
//go:embed all:catalogue
var catalogue embed.FS

// The data `harden apply` feeds to the target: the audit ruleset and the per-OS kernel-build
// recipe. Embedded for the same reason as everything else here, but this one was the worst of the
// three, because it did not fail: both were read with `os.ReadFile(...)` and the error DISCARDED,
// so a downloaded binary applied a plan with an EMPTY audit ruleset and an EMPTY kernel recipe and
// reported success. #286 at least stopped and said something.
//
//go:embed all:data
var data embed.FS

const ext = ".yml"

// Available reports whether a non-empty reference is embedded (a release build).
func Available() bool {
	return len(Names()) > 0
}

// Names lists the OS names embedded, sorted. Used by the commands that walk every reference
// (norms coverage, the OSCAL export) rather than reading one.
func Names() []string {
	entries, err := fs.ReadDir(fsys, "content")
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ext) {
			out = append(out, strings.TrimSuffix(e.Name(), ext))
		}
	}
	sort.Strings(out)
	return out
}

// Has reports whether the reference for <osName> is embedded.
func Has(osName string) bool {
	fi, err := fs.Stat(fsys, filepath.Join("content", osName+ext))
	return err == nil && !fi.IsDir()
}

// Read returns the embedded reference for <osName>, or an error if it is not embedded.
func Read(osName string) ([]byte, error) {
	return fsys.ReadFile(filepath.Join("content", osName+ext))
}

// Norms returns the embedded norm catalogue (docs/reference/norms.yml).
func Norms() ([]byte, error) {
	return catalogue.ReadFile(filepath.Join("catalogue", "norms"+ext))
}

// AuditRules returns the embedded audit ruleset (docs/reference/audit.rules).
func AuditRules() ([]byte, error) {
	return data.ReadFile(filepath.Join("data", "audit.rules"))
}

// Baseline returns the embedded baseline metadata (docs/reference/baseline.yml): the name, version,
// release date, licence and authority the OSCAL catalogue publishes about itself.
//
// readBaseline reads it off the disk and, on any error, keeps its hardcoded defaults. No published
// binary ever emitted the resulting catalogue, because `oscal` failed earlier on the reference it
// also could not read; embedding the reference is what would have let the command get this far and
// succeed with the WRONG metadata, which is the dangerous outcome. Measured on a build of this
// branch carrying the reference and not yet the baseline: version 0.0.0, released 1970-01-01.
// Silently wrong output from a compliance tool is worse than an error, because the artifact gets
// filed.
func Baseline() ([]byte, error) {
	return catalogue.ReadFile(filepath.Join("catalogue", "baseline"+ext))
}

// Probes returns the embedded behavioral probes (docs/reference/behavioral-probes.yml).
//
// Found after the fact, by grepping for every findRoot() still left: `pavois verify` read this file
// straight off the disk and returned the raw os.ReadFile error, so on a downloaded binary the
// command answered `open /root/docs/reference/behavioral-probes.yml: no such file or directory`.
// Same defect as #286, a fifth file, still shipping. It is data the binary needs and the user has
// no way to obtain, which is the test for whether something belongs here.
func Probes() ([]byte, error) {
	return data.ReadFile(filepath.Join("data", "behavioral-probes"+ext))
}

// KernelRecipe returns the embedded kernel-build recipe for <osName>, falling back to the legacy
// single kernel-build.sh when no per-OS file exists.
func KernelRecipe(osName string) ([]byte, error) {
	if b, err := data.ReadFile(filepath.Join("data", "kernel-build", osName+".sh")); err == nil {
		return b, nil
	}
	return data.ReadFile(filepath.Join("data", "kernel-build.sh"))
}
