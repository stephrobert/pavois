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
	"pavois/internal/render"
)

var (
	diffHTMLOut string
	diffJSONOut string
)

// diff compares two states: each is either a pavois hardening PLAN (.yml) or a scan
// report (.json): and shows what got fixed, regressed, (de)activated, plus the grade
// delta. Plan vs scan answers "did applying the plan actually fix the gaps it found?";
// scan vs scan confirms a remediation round moved the needle.
var diffCmd = &cobra.Command{
	Use:   "diff <before.json|plan.yml> <after.json|plan.yml>",
	Short: "Compare two states (scan report or plan): fixed, regressed, (de)activated, grade delta",
	Args:  cobra.ExactArgs(2),
	RunE:  runDiff,
}

func init() {
	diffCmd.Flags().StringVar(&diffHTMLOut, "html", "", "also write a self-contained campaign report to this path")
	diffCmd.Flags().StringVar(&diffJSONOut, "json", "", "also write the structured campaign delta to this path")
	rootCmd.AddCommand(diffCmd)
}

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
// status it recorded at plan time (compliant | gap | not_applicable): the same vocabulary
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
		return nil, fmt.Errorf("%s has no `rules:`: is it a Pavois plan?", path)
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

// normStatus maps the plan/scan vocabulary (gap | compliant | not_applicable) and the
// "absent" case (control present on only one side) onto the four campaign states.
func normStatus(s string, present bool) string {
	if !present {
		return "absent"
	}
	switch s {
	case "compliant":
		return "pass"
	case "gap":
		return "fail"
	case "not_applicable":
		return "na"
	default:
		return "na"
	}
}

func sevFromImpact(impact float64) string {
	switch {
	case impact >= 0.9:
		return "critical"
	case impact >= 0.7:
		return "high"
	case impact >= 0.4:
		return "medium"
	default:
		return "low"
	}
}

// metaFor extracts per-control metadata (title, domain, severity) for the report. Plans
// carry no severity/domain, so rich metadata comes from a scan report; ids are the fallback.
func metaFor(path string) map[string]render.CampItem {
	m := map[string]render.CampItem{}
	if strings.HasSuffix(path, ".yml") || strings.HasSuffix(path, ".yaml") {
		return m
	}
	rep, err := audit.Load(path)
	if err != nil {
		return m
	}
	for _, p := range rep.Profiles {
		for _, c := range p.Controls {
			dom := ""
			if v, ok := c.Tags["domain"].(string); ok {
				dom = v
			}
			m[c.ID] = render.CampItem{ID: c.ID, Title: c.Title, Domain: dom, Sev: sevFromImpact(c.Impact)}
		}
	}
	return m
}

// gradeInfo returns the grade for a scan report (empty for a plan, which has no score).
func gradeInfo(path string, isPlan bool) (letter string, passed, total int) {
	if isPlan {
		return "", 0, 0
	}
	rep, err := audit.Load(path)
	if err != nil {
		return "", 0, 0
	}
	res := audit.Evaluate(rep, "", "", "")
	l, _, _ := audit.GradeResult(res)
	return l, res.Passed, res.Total
}

// transitionBuckets groups every control id (over the union of both sides) by its
// "<from>><to>" transition, e.g. "fail>pass". Shared by `diff` and `bundle`.
func transitionBuckets(before, after map[string]string) map[string][]string {
	buckets := map[string][]string{}
	ids := map[string]bool{}
	for id := range before {
		ids[id] = true
	}
	for id := range after {
		ids[id] = true
	}
	for id := range ids {
		bs, bok := before[id]
		as, aok := after[id]
		key := normStatus(bs, bok) + ">" + normStatus(as, aok)
		buckets[key] = append(buckets[key], id)
	}
	for _, v := range buckets {
		sort.Strings(v)
	}
	return buckets
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

	buckets := transitionBuckets(before, after)

	// Transition matrix rows (the "scope delta").
	type rowDef struct{ key, label, kind string }
	defs := []rowDef{
		{"fail>pass", "Failed -> passed (fixed)", "good"},
		{"na>pass", "Newly applicable -> passed", "good"},
		{"absent>pass", "New control -> passed", "good"},
		{"pass>pass", "Passed -> passed (held)", "neutral"},
		{"fail>fail", "Failed -> failed (still failing)", "neutral"},
		{"na>fail", "Newly applicable -> failed", "bad"},
		{"absent>fail", "New control -> failed", "bad"},
		{"pass>fail", "Passed -> failed (regression)", "bad"},
		{"fail>na", "Failed -> not applicable", "neutral"},
		{"pass>na", "Passed -> not applicable", "neutral"},
		{"fail>absent", "Removed (was failing)", "neutral"},
		{"pass>absent", "Removed (was passing)", "neutral"},
	}
	var rows []render.CampRow
	for _, d := range defs {
		if n := len(buckets[d.key]); n > 0 {
			rows = append(rows, render.CampRow{Label: d.label, Count: n, Kind: d.kind})
		}
	}

	// Enriched sections (metadata from whichever side is a scan).
	meta := metaFor(args[1])
	for id, it := range metaFor(args[0]) {
		if _, ok := meta[id]; !ok {
			meta[id] = it
		}
	}
	mkSection := func(label, hint string, keys []string, bad, open bool) render.CampSection {
		var items []render.CampItem
		for _, k := range keys {
			for _, id := range buckets[k] {
				if it, ok := meta[id]; ok {
					items = append(items, it)
				} else {
					items = append(items, render.CampItem{ID: id})
				}
			}
		}
		return render.CampSection{Label: label, Hint: hint, Items: items, Bad: bad, Open: open}
	}
	sections := []render.CampSection{
		mkSection("Regressions (passed -> failed)", "Controls that were compliant before and broke after: review first.", []string{"pass>fail"}, true, true),
		mkSection("Fixed (failed -> passed)", "Gaps the remediation closed.", []string{"fail>pass"}, false, false),
		mkSection("Newly applicable, failing", "Controls the baseline made evaluable (a package/service now exists) that still fail.", []string{"na>fail", "absent>fail"}, false, false),
		mkSection("Still failing (failed -> failed)", "Gaps the remediation did not close (manual, install-time or kernel-build).", []string{"fail>fail"}, false, false),
		mkSection("Newly applicable, passing", "Controls the baseline made evaluable and that now pass.", []string{"na>pass", "absent>pass"}, false, false),
	}

	bGrade, bPass, bTotal := gradeInfo(args[0], beforePlan)
	aGrade, aPass, aTotal := gradeInfo(args[1], afterPlan)

	out := cmd.OutOrStdout()
	_, _ = fmt.Fprintf(out, "before: %s\n after: %s\n\n",
		summaryLine(args[0], before, beforePlan), summaryLine(args[1], after, afterPlan))
	if len(rows) == 0 {
		_, _ = fmt.Fprintln(out, "no change between the two states.")
	}
	for _, r := range rows {
		mark := " "
		switch r.Kind {
		case "good":
			mark = "+"
		case "bad":
			mark = "!"
		}
		_, _ = fmt.Fprintf(out, " %s %-36s %4d\n", mark, r.Label, r.Count)
	}
	// Always surface regressions in the terminal, they are the risk signal.
	if reg := buckets["pass>fail"]; len(reg) > 0 {
		_, _ = fmt.Fprintf(out, "\n! regressions (%d):\n", len(reg))
		for _, id := range reg {
			_, _ = fmt.Fprintf(out, "    %s\n", id)
		}
	}

	if diffHTMLOut != "" {
		data := render.CampaignData{
			BeforeLabel: filepath.Base(args[0]), AfterLabel: filepath.Base(args[1]),
			BeforeGrade: orDash(bGrade), AfterGrade: orDash(aGrade),
			BeforePass: bPass, BeforeTotal: bTotal, AfterPass: aPass, AfterTotal: aTotal,
			Rows: rows, Sections: sections,
		}
		if err := os.WriteFile(diffHTMLOut, []byte(render.Campaign(data)), 0o600); err != nil {
			return fmt.Errorf("write %s: %w", diffHTMLOut, err)
		}
		_, _ = fmt.Fprintf(out, "\ncampaign report -> %s\n", diffHTMLOut)
	}
	if diffJSONOut != "" {
		payload := map[string]any{
			"before":      map[string]any{"source": filepath.Base(args[0]), "grade": bGrade, "passed": bPass, "total": bTotal},
			"after":       map[string]any{"source": filepath.Base(args[1]), "grade": aGrade, "passed": aPass, "total": aTotal},
			"transitions": bucketCounts(buckets),
			"controls":    buckets,
		}
		blob, _ := json.MarshalIndent(payload, "", "  ")
		if err := os.WriteFile(diffJSONOut, blob, 0o600); err != nil {
			return fmt.Errorf("write %s: %w", diffJSONOut, err)
		}
		_, _ = fmt.Fprintf(out, "campaign delta -> %s\n", diffJSONOut)
	}
	return nil
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func bucketCounts(buckets map[string][]string) map[string]int {
	c := map[string]int{}
	for k, v := range buckets {
		c[k] = len(v)
	}
	return c
}
