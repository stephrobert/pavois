package cmd

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/spf13/cobra"

	"pavois/internal/audit"
)

var (
	bundlePlan      string
	bundleReports   []string
	bundleReboot    string
	bundleException string
	bundleOut       string
)

// bundle assembles a tamper-evident **evidence package** from a hardening campaign:
// the before/after scans, the plan that was applied, the reports, an optional
// reboot-proof and exceptions file, plus a manifest (tool + ruleset version, target,
// grade delta, transition matrix) and a checksums file. The manifest's own SHA-256 is
// the single value an operator signs/publishes to make the whole bundle opposable. This
// is what turns "a strong technical result" into "audit-ready evidence" (ChatGPT review).
var bundleCmd = &cobra.Command{
	Use:   "bundle <before.json> <after.json>",
	Short: "Assemble a signed-ready evidence package (before/after, plan, reports, manifest + checksums)",
	Args:  cobra.ExactArgs(2),
	RunE:  runBundle,
}

func init() {
	bundleCmd.Flags().StringVar(&bundlePlan, "plan", "", "hardening plan that was applied (.yml)")
	bundleCmd.Flags().StringArrayVar(&bundleReports, "report", nil, "report file to include (HTML/JSON/...), repeatable")
	bundleCmd.Flags().StringVar(&bundleReboot, "reboot-proof", "", "reboot-proof artifact (boot_id / uptime captured post-reboot)")
	bundleCmd.Flags().StringVar(&bundleException, "exceptions", "", "formal exceptions file (who excluded what, why, until when)")
	bundleCmd.Flags().StringVarP(&bundleOut, "out", "o", "", "output directory (default: evidence-bundle-<timestamp>)")
	rootCmd.AddCommand(bundleCmd)
}

type bundleArtifact struct {
	File   string `json:"file"`
	Role   string `json:"role"`
	SHA256 string `json:"sha256"`
	Bytes  int64  `json:"bytes"`
}

func sha256File(path string) (string, int64, error) {
	f, err := os.Open(path) //nolint:gosec // operator-supplied report path, read-only
	if err != nil {
		return "", 0, err
	}
	defer func() { _ = f.Close() }()
	h := sha256.New()
	n, err := io.Copy(h, f)
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(h.Sum(nil)), n, nil
}

// copyInto copies src into dir under its base name and returns the recorded artifact.
func copyInto(src, dir, role string) (bundleArtifact, error) {
	sum, n, err := sha256File(src)
	if err != nil {
		return bundleArtifact{}, err
	}
	base := filepath.Base(src)
	data, err := os.ReadFile(src) //nolint:gosec // operator-supplied path
	if err != nil {
		return bundleArtifact{}, err
	}
	// base is filepath.Base(src) (no traversal) and dir is operator-chosen.
	dest := filepath.Join(dir, base)
	if err := os.WriteFile(dest, data, 0o600); err != nil { //nolint:gosec // see above: no path traversal
		return bundleArtifact{}, err
	}
	return bundleArtifact{File: base, Role: role, SHA256: sum, Bytes: n}, nil
}

func runBundle(cmd *cobra.Command, args []string) error {
	beforePath, afterPath := args[0], args[1]
	before, beforePlan, err := statusesFor(beforePath)
	if err != nil {
		return err
	}
	after, afterPlan, err := statusesFor(afterPath)
	if err != nil {
		return err
	}

	out := bundleOut
	if out == "" {
		out = "evidence-bundle-" + time.Now().Format("20060102-150405")
	}
	if err := os.MkdirAll(out, 0o755); err != nil { //nolint:gosec // a published bundle dir is world-readable by design
		return err
	}

	// Required artifacts (before + after), then the optional ones.
	type src struct{ path, role string }
	srcs := []src{{beforePath, "scan-before"}, {afterPath, "scan-after"}}
	if bundlePlan != "" {
		srcs = append(srcs, src{bundlePlan, "plan"})
	}
	for _, r := range bundleReports {
		srcs = append(srcs, src{r, "report"})
	}
	if bundleReboot != "" {
		srcs = append(srcs, src{bundleReboot, "reboot-proof"})
	}
	if bundleException != "" {
		srcs = append(srcs, src{bundleException, "exceptions"})
	}
	var artifacts []bundleArtifact
	for _, s := range srcs {
		a, err := copyInto(s.path, out, s.role)
		if err != nil {
			return fmt.Errorf("bundle %s: %w", s.path, err)
		}
		artifacts = append(artifacts, a)
	}

	// Campaign delta + grades.
	buckets := transitionBuckets(before, after)
	bGrade, bPass, bTotal := gradeInfo(beforePath, beforePlan)
	aGrade, aPass, aTotal := gradeInfo(afterPath, afterPlan)
	campaign := map[string]any{
		"transitions":           bucketCounts(buckets),
		"fixed":                 len(buckets["fail>pass"]),
		"regressions":           buckets["pass>fail"],
		"still_failing":         len(buckets["fail>fail"]),
		"newly_applicable_pass": len(buckets["na>pass"]) + len(buckets["absent>pass"]),
		"newly_applicable_fail": len(buckets["na>fail"]) + len(buckets["absent>fail"]),
	}
	deltaBlob, _ := json.MarshalIndent(map[string]any{"campaign": campaign, "controls": buckets}, "", "  ")
	if err := os.WriteFile(filepath.Join(out, "campaign-delta.json"), deltaBlob, 0o600); err != nil {
		return err
	}
	dSum, dN, _ := sha256File(filepath.Join(out, "campaign-delta.json"))
	artifacts = append(artifacts, bundleArtifact{File: "campaign-delta.json", Role: "delta", SHA256: dSum, Bytes: dN})

	// Target + ruleset version from the after report (best-effort).
	platform, release, ruleset := "", "", ""
	if rep, e := audit.Load(afterPath); e == nil {
		platform, release = rep.Platform.Name, rep.Platform.Release
		if len(rep.Profiles) > 0 {
			ruleset = rep.Profiles[0].Version
		}
	}

	manifest := map[string]any{
		"format":          "pavois-evidence-bundle/v1",
		"pavois_version":  version,
		"ruleset_version": ruleset,
		"generated":       time.Now().UTC().Format(time.RFC3339),
		"target":          map[string]string{"platform": platform, "release": release},
		"before":          map[string]any{"file": filepath.Base(beforePath), "grade": bGrade, "passed": bPass, "total": bTotal},
		"after":           map[string]any{"file": filepath.Base(afterPath), "grade": aGrade, "passed": aPass, "total": aTotal},
		"campaign":        campaign,
		"artifacts":       artifacts,
	}
	manBlob, _ := json.MarshalIndent(manifest, "", "  ")
	if err := os.WriteFile(filepath.Join(out, "manifest.json"), manBlob, 0o600); err != nil {
		return err
	}

	// checksums.txt over every artifact + the manifest (for `sha256sum -c`).
	var cks string
	for _, a := range artifacts {
		cks += fmt.Sprintf("%s  %s\n", a.SHA256, a.File)
	}
	manSum, _, _ := sha256File(filepath.Join(out, "manifest.json"))
	cks += fmt.Sprintf("%s  %s\n", manSum, "manifest.json")
	if err := os.WriteFile(filepath.Join(out, "checksums.txt"), []byte(cks), 0o600); err != nil {
		return err
	}

	o := cmd.OutOrStdout()
	_, _ = fmt.Fprintf(o, "evidence bundle -> %s/\n", out)
	_, _ = fmt.Fprintf(o, "  %d artifacts · before %s -> after %s · %d fixed, %d regressions\n",
		len(artifacts), orDash(bGrade), orDash(aGrade), len(buckets["fail>pass"]), len(buckets["pass>fail"]))
	_, _ = fmt.Fprintf(o, "  manifest sha256: %s\n", manSum)
	_, _ = fmt.Fprintln(o, "  sign/publish that digest to make the bundle opposable (e.g. minisign/cosign/gpg on checksums.txt).")
	return nil
}
