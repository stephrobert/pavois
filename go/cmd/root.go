// Package cmd câble la CLI de Pavois (cobra), façon pitstop : commande racine,
// scan/profiles/version, et traduction du résultat en code de sortie pour la CI.
package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"

	screport "github.com/stephrobert/scankit/report"
)

// ComplianceError signale une non-conformité bloquante (note sous le seuil) :
// code de sortie 1, distinct du code 2 réservé aux erreurs techniques.
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
	// Bandeau (logo + version + tagline) dès le lancement de toute commande.
	PersistentPreRun: func(_ *cobra.Command, _ []string) {
		screport.Banner(os.Stderr, bannerOpts())
	},
}

// Execute lance la racine et traduit en code de sortie : 0 conforme, 1
// non-conformité (sous le seuil), 2 erreur technique.
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
	_, _ = fmt.Fprintln(os.Stderr, "erreur:", err)
	os.Exit(2)
}

// findRoot localise la racine du dépôt (dossier contenant profiles/).
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
