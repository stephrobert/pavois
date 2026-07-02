// Package cmd wires up the Pavois CLI (cobra), pitstop-style: root command,
// scan/profiles/version, and translation of the result into an exit code for CI.
package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	screport "github.com/stephrobert/scankit/report"
)

// ComplianceError signals a blocking non-compliance (grade below the threshold):
// exit code 1, distinct from code 2 reserved for technical errors.
type ComplianceError struct{ Points, Threshold int }

func (e *ComplianceError) Error() string {
	return fmt.Sprintf("grade %d/100 < threshold %d/100", e.Points, e.Threshold)
}

var rootCmd = &cobra.Command{
	Use:   "pavois",
	Short: "Pavois — Effective Linux Compliance (CINC/InSpec)",
	Long: `Pavois audits the EFFECTIVE configuration of a Linux system (sshd -T, sysctl,
systemctl, dpkg/rpm...) via CINC Auditor, maps each control to N standards
(SOCLE / CIS / ANSSI BP-028 / PCI-DSS / NIST / STIG) and outputs an A-E grade.

  pavois scan local --profile profiles/linux/debian12 --sudo
  pavois scan user@host --key ~/.ssh/id --standard cis --level 1 --fail-under 50`,
	SilenceUsage:  true,
	SilenceErrors: true,
	// Banner (logo + version + tagline) as soon as any command is launched.
	PersistentPreRun: func(_ *cobra.Command, _ []string) {
		screport.Banner(os.Stderr, bannerOpts())
	},
}

// Execute runs the root command and translates the result into an exit code: 0 compliant, 1
// non-compliance (below the threshold), 2 technical error.
func Execute() {
	err := rootCmd.Execute()
	if err == nil {
		return
	}
	var ce *ComplianceError
	if errors.As(err, &ce) {
		_, _ = fmt.Fprintln(os.Stderr, "pavois:", ce.Error())
		os.Exit(1)
	}
	_, _ = fmt.Fprintln(os.Stderr, "error:", err)
	os.Exit(2)
}

// findRoot locates the repository root (directory containing profiles/).
func findRoot() string {
	if r := os.Getenv("PAVOIS_ROOT"); r != "" {
		return r
	}
	var dirs []string
	if wd, err := os.Getwd(); err == nil {
		dirs = append(dirs, wd)
	}
	if ex, err := os.Executable(); err == nil {
		dirs = append(dirs, filepath.Dir(ex))
	}
	for _, d := range dirs {
		for cur := d; ; {
			if fi, err := os.Stat(filepath.Join(cur, "profiles")); err == nil && fi.IsDir() {
				return cur
			}
			parent := filepath.Dir(cur)
			if parent == cur {
				break
			}
			cur = parent
		}
	}
	wd, _ := os.Getwd()
	return wd
}
