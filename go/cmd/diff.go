package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"

	"pavois/internal/audit"
)

// diff compares two states — each is either a pavois hardening PLAN (.yml) or a scan
// report (.json) — and shows what got fixed, regressed, (de)activated, plus the grade
// delta. Plan vs scan answers "did applying the plan actually fix the gaps it found?";
// scan vs scan confirms a remediation round moved the needle.
var diffCmd = &cobra.Command{
	Use:   "diff <before.json|plan.yml> <after.json|plan.yml>",
	Short: "Compare two states (scan report or plan): fixed, regressed, (de)activated, grade delta",
	Args:  cobra.ExactArgs(2),
	RunE:  runDiff,
}

func init() { rootCmd.AddCommand(diffCmd) }

func scanStatuses(path string) (map[string]string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var s inspecScan
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	st := map[string]string{}
	for _, p := range s.Profiles {
		for _, c := range p.Controls {
			st[c.ID] = controlStatus(c.Results)
		}
	}
	return st, nil
}

// planStatuses reads a Pavois plan (hardening-plan-<os>.yml) and returns the per-control
// status it recorded at plan time (compliant | gap | not_applicable) — the same vocabulary
// as a scan, so the two can be diffed directly.
func planStatuses(path string) (map[string]string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var p planFile
	if err := yaml.Unmarshal(raw, &p); err != nil {
		return nil, fmt.Errorf("parse plan %s: %w", path, err)
	}
	if len(p.Rules) == 0 {
		return nil, fmt.Errorf("%s has no `rules:` — is it a Pavois plan?", path)
	}
	st := map[string]string{}
	for id, r := range p.Rules {
		st[id] = r.Status
	}
	return st, nil
}

// statusesFor reads either a Pavois plan (.yml/.yaml) or an InSpec scan report (.json).
func statusesFor(path string) (st map[string]string, isPlan bool, err error) {
	if strings.HasSuffix(path, ".yml") || strings.HasSuffix(path, ".yaml") {
		st, err = planStatuses(path)
		return st, true, err
	}
	st, err = scanStatuses(path)
	return st, false, err
}

func summaryLine(path string, st map[string]string, isPlan bool) string {
	if !isPlan {
		return gradeLine(path)
	}
	comp := 0
	for _, s := range st {
		if s == "compliant" {
			comp++
		}
	}
	return fmt.Sprintf("plan %s · %d/%d compliant", filepath.Base(path), comp, len(st))
}

func gradeLine(path string) string {
	rep, err := audit.Load(path)
	if err != nil {
		return "?"
	}
	res := audit.Evaluate(rep, "", "", "")
	l, p, rq := audit.GradeResult(res)
	q := ""
	if rq {
		q = fmt.Sprintf(" · %d runtime-only", res.Qualified)
	}
	return fmt.Sprintf("%s (%d/100 · %d/%d pass%s)", l, p, res.Passed, res.Total, q)
}

func runDiff(cmd *cobra.Command, args []string) error {
	before, beforePlan, err := statusesFor(args[0])
	if err != nil {
		return err
	}
	after, afterPlan, err := statusesFor(args[1])
	if err != nil {
		return err
	}

	var fixed, regressed, activated, deactivated, added, removed []string
	for cid, a := range after {
		b, ok := before[cid]
		switch {
		case !ok:
			added = append(added, cid)
		case b == "gap" && a == "compliant":
			fixed = append(fixed, cid)
		case b == "compliant" && a == "gap":
			regressed = append(regressed, cid)
		case b == "not_applicable" && a != "not_applicable":
			activated = append(activated, fmt.Sprintf("%s (%s)", cid, a))
		case b != "not_applicable" && a == "not_applicable":
			deactivated = append(deactivated, cid)
		}
	}
	for cid := range before {
		if _, ok := after[cid]; !ok {
			removed = append(removed, cid)
		}
	}

	out := cmd.OutOrStdout()
	fmt.Fprintf(out, "before: %s\n after: %s\n\n",
		summaryLine(args[0], before, beforePlan), summaryLine(args[1], after, afterPlan))
	section := func(sym, label string, list []string) {
		if len(list) == 0 {
			return
		}
		sort.Strings(list)
		fmt.Fprintf(out, "%s %s (%d)\n", sym, label, len(list))
		for _, c := range list {
			fmt.Fprintf(out, "    %s\n", c)
		}
	}
	section("✔", "fixed (gap → pass)", fixed)
	section("✗", "regressed (pass → gap)", regressed)
	section("+", "activated (n/a → active)", activated)
	section("·", "now not applicable", deactivated)
	section("›", "new controls", added)
	section("‹", "removed controls", removed)
	if len(fixed)+len(regressed)+len(activated)+len(deactivated)+len(added)+len(removed) == 0 {
		fmt.Fprintln(out, "no change between the two states.")
	}
	return nil
}
