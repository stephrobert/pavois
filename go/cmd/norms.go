package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

// `pavois norms` exposes the norm catalogue (docs/reference/norms.yml): each standard with the
// version Pavois's mappings target, its authority and source: enriched with LIVE coverage from
// the rule base (how many controls and distinct values map to each norm, per OS). This is the
// self-describing face of the source of truth: the API an auditor consults to trust which standard
// versions Pavois covers, and the baseline the norm-watcher will diff live sources against.
var normsPretty bool

var normsCmd = &cobra.Command{
	Use:   "norms",
	Short: "Output the norm catalogue (standards, versions, authorities) + live coverage as JSON",
	Long: "Emit the standards Pavois maps to: CIS (per-OS benchmark version), ANSSI-BP-028,\n" +
		"NIST 800-53/800-171, PCI-DSS, STIG: each with its version, authority and source, plus\n" +
		"live per-OS coverage from the rule base. The self-describing reference API.",
	RunE: runNorms,
}

func init() {
	normsCmd.Flags().BoolVar(&normsPretty, "pretty", true, "pretty-print the JSON")
	rootCmd.AddCommand(normsCmd)
}

func runNorms(_ *cobra.Command, _ []string) error {
	root := findRoot()
	raw, err := readNormCatalogue(root)
	if err != nil {
		return err
	}
	var catalogue map[string]any
	if err := yaml.Unmarshal(raw, &catalogue); err != nil {
		return fmt.Errorf("parse norm catalogue: %w", err)
	}

	// Live coverage: for each OS reference, count controls carrying each norm + distinct values.
	// The reference comes from the checkout or from the binary itself, so this reports real
	// coverage on a downloaded binary instead of silently reporting none (#286).
	coverage := map[string]any{}
	for _, osName := range referenceOSes(root) {
		b, err := readReference(root, osName)
		if err != nil {
			continue
		}
		var doc struct {
			Rules map[string]struct {
				Norms map[string]any `yaml:"norms"`
			} `yaml:"rules"`
		}
		if yaml.Unmarshal(b, &doc) != nil {
			continue
		}
		perNorm := map[string]map[string]bool{}
		for _, e := range doc.Rules {
			for k, v := range e.Norms {
				if perNorm[k] == nil {
					perNorm[k] = map[string]bool{}
				}
				if list, ok := v.([]any); ok {
					for _, x := range list {
						perNorm[k][fmt.Sprint(x)] = true
					}
				} else {
					perNorm[k][fmt.Sprint(v)] = true
				}
			}
		}
		counts := map[string]int{}
		for k, set := range perNorm {
			counts[k] = len(set)
		}
		coverage[osName] = map[string]any{"controls": len(doc.Rules), "mapped_values": counts}
	}

	out := map[string]any{}
	for k, v := range catalogue {
		out[k] = v
	}
	out["coverage"] = coverage

	enc := json.NewEncoder(os.Stdout)
	if normsPretty {
		enc.SetIndent("", "  ")
	}
	return enc.Encode(out)
}
