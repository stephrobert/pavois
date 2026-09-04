package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// norm describes an auditable standard and its levels.
type norm struct {
	Key, Name, Desc, Levels string
}

// standards: the supported standards (--standard key) and their levels.
// Mappings and levels come from the Pavois reference (docs/reference/
// pavois-content/); Pavois invents neither mapping nor value.
var standards = []norm{
	{"bp28", "ANSSI BP-028",
		"Configuration hardening guide for GNU/Linux systems: French national\n    cybersecurity agency (ANSSI).",
		"minimal · intermediary · enhanced · high (cumulative, --level)"},
	{"cis", "CIS Benchmark",
		"Center for Internet Security: consensus-based hardening benchmark.",
		"1 · 2  (and server/workstation profiles) (cumulative, --level)"},
	{"pci-dss", "PCI-DSS",
		"Payment Card Industry Data Security Standard: requirements for systems\n    handling payment card data.",
		"(no level)"},
	{"nist", "NIST SP 800-171",
		"Protecting Controlled Unclassified Information: US NIST institute.",
		"(no level)"},
	{"stig", "DISA STIG",
		"Security Technical Implementation Guide: US Defense Information Systems\n    Agency (DoD).",
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
		_, _ = fmt.Fprintln(out, "Auditable standards (--standard option):")
		_, _ = fmt.Fprintln(out)
		for _, n := range standards {
			_, _ = fmt.Fprintf(out, "  %-9s %s\n", n.Key, n.Name)
			_, _ = fmt.Fprintf(out, "    %s\n", n.Desc)
			_, _ = fmt.Fprintf(out, "    Levels: %s\n\n", n.Levels)
		}
		_, _ = fmt.Fprintln(out, "A control = one neutral internal ID + N standard mappings (per-standard view).")
		_, _ = fmt.Fprintln(out, `Without --standard: "all standards" view (the strictest of each).`)
		_, _ = fmt.Fprintln(out, "E.g.: pavois scan local --standard bp28 --level high")
		return nil
	},
}

func init() { rootCmd.AddCommand(standardsCmd) }
