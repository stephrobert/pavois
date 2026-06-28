package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// norm décrit une réglementation auditable et ses niveaux.
type norm struct {
	Key, Name, Desc, Levels string
}

// standards : les réglementations supportées (clé --standard) et leurs niveaux.
// Mappings et niveaux proviennent de la référence Pavois (docs/reference/
// pavois-content/) ; Pavois n'invente ni mapping ni valeur.
var standards = []norm{
	{"bp28", "ANSSI BP-028",
		"Configuration hardening guide for GNU/Linux systems — French national\n    cybersecurity agency (ANSSI).",
		"minimal · intermediary · enhanced · high (cumulative, --level)"},
	{"cis", "CIS Benchmark",
		"Center for Internet Security — consensus-based hardening benchmark.",
		"1 · 2  (and server/workstation profiles) (cumulative, --level)"},
	{"pci-dss", "PCI-DSS",
		"Payment Card Industry Data Security Standard — requirements for systems\n    handling payment card data.",
		"(no level)"},
	{"nist", "NIST SP 800-171",
		"Protecting Controlled Unclassified Information — US NIST institute.",
		"(no level)"},
	{"stig", "DISA STIG",
		"Security Technical Implementation Guide — US Defense Information Systems\n    Agency (DoD).",
		"(CAT I/II/III severity on the DISA side)"},
	{"posture", "Posture (Pavois)",
		"Pavois-specific hardening, with NO standard mapping (e.g. ASLR, anti-malware,\n    firewall installed). In-house risk rating, as a complementary layer.",
		"(no level)"},
}

var standardsCmd = &cobra.Command{
	Use:     "standards",
	Aliases: []string{"normes"},
	Short:   "Explain the auditable standards (--standard) and their levels",
	Args:    cobra.NoArgs,
	RunE: func(cmd *cobra.Command, _ []string) error {
		out := cmd.OutOrStdout()
		fmt.Fprintln(out, "Auditable standards (--standard option):")
		fmt.Fprintln(out)
		for _, n := range standards {
			fmt.Fprintf(out, "  %-9s %s\n", n.Key, n.Name)
			fmt.Fprintf(out, "    %s\n", n.Desc)
			fmt.Fprintf(out, "    Levels: %s\n\n", n.Levels)
		}
		fmt.Fprintln(out, "A control = one neutral internal ID + N standard mappings (per-standard view).")
		fmt.Fprintln(out, `Without --standard: "all standards" view (the strictest of each).`)
		fmt.Fprintln(out, "E.g.: pavois scan local --standard bp28 --level high")
		return nil
	},
}

func init() { rootCmd.AddCommand(standardsCmd) }
