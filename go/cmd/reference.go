package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"pavois/internal/reference"
)

// The hardening reference, read the way a released binary can actually read it.
//
// Four commands used to do this by hand, each with its own os.ReadFile under findRoot():
//
//	harden.go   plan a remediation from the scan
//	rules.go    print one control, or the whole set
//	norms.go    norm coverage per OS
//	oscal.go    the OSCAL catalogue
//
// findRoot() walks up looking for profiles/ and falls back to the CURRENT DIRECTORY when it finds
// none, which is always the case for a downloaded binary. So all four resolved the reference
// against wherever the user happened to be standing, and all four failed with a path that moved
// when you cd'd. #286 reported it against `harden plan`; it was never a harden bug.
//
// Disk first, embedded second, deliberately: a contributor editing docs/reference/ must see their
// edit take effect without rebuilding, and that is the case the on-disk copy exists for.

// referenceFile is where a checkout keeps the reference for one OS.
func referenceFile(root, osName string) string {
	return filepath.Join(root, "docs", "reference", "pavois-content", osName+".yml")
}

// readReference returns the reference for osName: the repository's copy when there is one, the
// embedded copy otherwise.
//
// The error matters as much as the lookup. The old one was `open /root/docs/reference/
// pavois-content/ubuntu2404.yml: no such file or directory`, which names an internal repository
// path and tells the reader nothing they can act on: there is no package to install and no file to
// download that would create it.
func readReference(root, osName string) ([]byte, error) {
	if b, err := os.ReadFile(referenceFile(root, osName)); err == nil {
		return b, nil
	}
	if b, err := reference.Read(osName); err == nil {
		return b, nil
	}
	known := referenceOSes(root)
	if len(known) == 0 {
		return nil, fmt.Errorf("no hardening reference for %s: this binary embeds none and none is "+
			"on disk. A release binary carries every supported system; in a checkout, run "+
			"`mise run regen`", osName)
	}
	return nil, fmt.Errorf("no hardening reference for %s: known systems are %s",
		osName, strings.Join(known, ", "))
}

// readNormCatalogue returns docs/reference/norms.yml, from the checkout or from the binary.
//
// Missed on the first pass at #286, which fixed the per-OS references and left this one: `pavois
// norms` still answered `read norm catalogue: open /tmp/docs/reference/norms.yml`. It was found by
// the VM scenario, not by any test running inside the repository, which is the whole argument for
// having the scenario.
func readNormCatalogue(root string) ([]byte, error) {
	if b, err := os.ReadFile(filepath.Join(root, "docs", "reference", "norms.yml")); err == nil {
		return b, nil
	}
	if b, err := reference.Norms(); err == nil {
		return b, nil
	}
	return nil, fmt.Errorf("no norm catalogue: this binary embeds none and none is on disk. " +
		"In a checkout, run `mise run regen`")
}

// readAuditRules and readKernelRecipe feed `harden apply`. They return an ERROR rather than an
// empty slice, which is the whole point of their existence.
//
// Both were `os.ReadFile(filepath.Join(findRoot(), ...))` with the error assigned to `_`. Outside a
// checkout, findRoot() is the current directory, the read failed, and apply carried on with an
// empty audit ruleset and an empty kernel recipe. It hardened the machine, skipped those two
// domains entirely, and reported success. A silent no-op on a hardening tool is worse than a
// crash: the operator believes the host is covered.

func readAuditRules(root string) ([]byte, error) {
	if b, err := os.ReadFile(filepath.Join(root, "docs", "reference", "audit.rules")); err == nil {
		return b, nil
	}
	b, err := reference.AuditRules()
	if err != nil {
		return nil, fmt.Errorf("no audit ruleset: this binary embeds none and none is on disk. " +
			"In a checkout, run `mise run regen`")
	}
	return b, nil
}

// readBaselineMeta returns docs/reference/baseline.yml, from the checkout or from the binary.
// Its caller keeps hardcoded defaults for the case where neither exists, so the ONLY symptom of
// this read failing is an OSCAL catalogue that publishes itself as version 0.0.0, released
// 1970-01-01. Two releases did exactly that.
func readBaselineMeta(root string) ([]byte, error) {
	if b, err := os.ReadFile(filepath.Join(root, "docs", "reference", "baseline.yml")); err == nil {
		return b, nil
	}
	return reference.Baseline()
}

// readBehavioralProbes returns docs/reference/behavioral-probes.yml, from the checkout or from the
// binary. `pavois verify` used to read it with a bare os.ReadFile and return that error verbatim,
// so outside a checkout it answered with an internal repository path the user cannot create.
func readBehavioralProbes(root string) ([]byte, error) {
	if b, err := os.ReadFile(filepath.Join(root, "docs", "reference", "behavioral-probes.yml")); err == nil {
		return b, nil
	}
	b, err := reference.Probes()
	if err != nil || len(b) == 0 {
		return nil, fmt.Errorf("no behavioral probes: this binary embeds none and none is on disk. " +
			"In a checkout, run `mise run regen`")
	}
	return b, nil
}

func readKernelRecipe(root, osName string) ([]byte, error) {
	for _, p := range []string{
		filepath.Join(root, "docs", "reference", "kernel-build", osName+".sh"),
		filepath.Join(root, "docs", "reference", "kernel-build.sh"),
	} {
		if b, err := os.ReadFile(p); err == nil && len(b) > 0 {
			return b, nil
		}
	}
	b, err := reference.KernelRecipe(osName)
	if err != nil || len(b) == 0 {
		return nil, fmt.Errorf("no kernel-build recipe for %s: this binary embeds none and none is "+
			"on disk. In a checkout, run `mise run regen`", osName)
	}
	return b, nil
}

// referenceOSes lists every system a reference exists for, merging the checkout and the embedded
// copy. Used by the commands that walk all of them rather than reading one.
func referenceOSes(root string) []string {
	seen := map[string]bool{}
	for _, n := range reference.Names() {
		seen[n] = true
	}
	entries, _ := os.ReadDir(filepath.Join(root, "docs", "reference", "pavois-content"))
	for _, e := range entries {
		if !e.IsDir() && filepath.Ext(e.Name()) == ".yml" {
			seen[strings.TrimSuffix(e.Name(), ".yml")] = true
		}
	}
	out := make([]string, 0, len(seen))
	for n := range seen {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}
