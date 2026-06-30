package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

// `pavois rules` serves the Pavois rule base as JSON — the public contract of the source of
// truth (the per-distro reference), the seed of the rules API. Filter by OS, standard, domain.
// Pavois's base is authoritative; this exposes it so other tools (auditors, dashboards) consume
// it without parsing SSG. Norm mappings (cis/bp28/nist/...) travel with each rule for traceability.
var (
	ruOS       string
	ruStandard string
	ruDomain   string
	ruID       string
	ruPretty   bool
)

var rulesCmd = &cobra.Command{
	Use:   "rules",
	Short: "Output the Pavois rule base as JSON (the reference API)",
	Long: "Emit the Pavois rule base as JSON — id, title, domain, severity, the real norm\n" +
		"mappings (cis/bp28/nist/pci-dss/stig) and per-norm thresholds, the check and the\n" +
		"remediation. Filter with --os/--standard/--domain. This is the consumable contract of\n" +
		"Pavois's source-of-truth reference; it does not need a target.",
	RunE: runRules,
}

func init() {
	rulesCmd.Flags().StringVar(&ruOS, "os", "debian12", "OS reference to read (e.g. debian12, ubuntu2404)")
	rulesCmd.Flags().StringVar(&ruStandard, "standard", "", "only rules mapped to this standard: bp28|cis|nist|pci-dss|stig")
	rulesCmd.Flags().StringVar(&ruDomain, "domain", "", "only rules in this domain")
	rulesCmd.Flags().StringVar(&ruID, "id", "", "only this control id (e.g. ssh-disable-root-login)")
	rulesCmd.Flags().BoolVar(&ruPretty, "pretty", true, "pretty-print the JSON")
	rootCmd.AddCommand(rulesCmd)
}

func runRules(cmd *cobra.Command, _ []string) error {
	path := filepath.Join(findRoot(), "docs", "reference", "pavois-content", ruOS+".yml")
	raw, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read reference %s: %w", ruOS, err)
	}
	var doc struct {
		Rules map[string]map[string]any `yaml:"rules"`
	}
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		return fmt.Errorf("parse reference: %w", err)
	}

	ids := make([]string, 0, len(doc.Rules))
	for id := range doc.Rules {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	out := make([]map[string]any, 0, len(ids))
	for _, id := range ids {
		if ruID != "" && id != ruID {
			continue
		}
		e := doc.Rules[id]
		norms, _ := e["norms"].(map[string]any)
		if ruStandard != "" {
			if norms == nil || norms[ruStandard] == nil {
				continue
			}
		}
		if ruDomain != "" && fmt.Sprint(e["domain"]) != ruDomain {
			continue
		}
		rule := map[string]any{"id": id}
		for k, v := range e {
			rule[k] = v
		}
		if rem, ok := e["remediation"].(map[string]any); ok {
			rule["remediable"] = true
			rule["remediation_resource"] = rem["resource"]
		} else {
			rule["remediable"] = false
		}
		out = append(out, rule)
	}

	res := map[string]any{"os": ruOS, "standard": ruStandard, "domain": ruDomain, "count": len(out), "rules": out}
	enc := json.NewEncoder(os.Stdout)
	if ruPretty {
		enc.SetIndent("", "  ")
	}
	return enc.Encode(res)
}
