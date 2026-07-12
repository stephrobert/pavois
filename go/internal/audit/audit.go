// Package audit translates a CINC/InSpec JSON report into scankit findings, filters
// by standard + level, and computes the A->E grade (Plumber model: loss based on the
// NUMBER of failures per severity, critical penalty).
package audit

import (
	"encoding/json"
	"fmt"
	"math"
	"os"
	"sort"
	"strings"

	"github.com/stephrobert/scankit/finding"
	"github.com/stephrobert/scankit/scoring"
)

// Report is the (partial) structure of the InSpec JSON report.
type Report struct {
	Platform struct {
		Name    string `json:"name"`
		Release string `json:"release"`
	} `json:"platform"`
	Profiles []struct {
		Title    string    `json:"title"`
		Version  string    `json:"version"`
		Controls []Control `json:"controls"`
	} `json:"profiles"`
}

// Control is an InSpec control and its results.
type Control struct {
	ID     string           `json:"id"`
	Title  string           `json:"title"`
	Desc   string           `json:"desc"`
	Impact float64          `json:"impact"`
	Tags   map[string]any   `json:"tags"`
	Refs   []map[string]any `json:"refs"`
	// cinc fills this for a control listed in the profile's waivers.yml: it carries the
	// justification an auditor reads, and it is how we tell an ACCEPTED RISK from a plain N/A.
	WaiverData struct {
		Justification string `json:"justification"`
		Run           *bool  `json:"run"`
	} `json:"waiver_data"`
	Results []struct {
		Status      string `json:"status"`
		CodeDesc    string `json:"code_desc"`
		Message     string `json:"message"`
		SkipMessage string `json:"skip_message"`
	} `json:"results"`
}

// normKeys: recognized standards (display order). The level is carried by
// level_<standard> (e.g. level_bp28, level_cis).
var normKeys = []string{"bp28", "cis", "pci-dss", "nist", "stig"}

var levelOrder = map[string][]string{
	"bp28": {"minimal", "intermediary", "enhanced", "high"},
	"cis":  {"1", "2"},
}

// Load reads and decodes an InSpec JSON report.
func Load(path string) (*Report, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var r Report
	if err := json.Unmarshal(b, &r); err != nil {
		return nil, fmt.Errorf("unreadable InSpec JSON: %w", err)
	}
	return &r, nil
}

func tagStr(c Control, key string) string {
	if v, ok := c.Tags[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

// severity: the standards' actual scale (3 levels). The SSG does not classify as
// "critical" and standards do not override the severity.
func severity(impact float64) string {
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

func status(c Control) string {
	if len(c.Results) == 0 {
		return "empty"
	}
	failed, allSkipped := false, true
	for _, r := range c.Results {
		if r.Status == "failed" {
			failed = true
		}
		if r.Status != "skipped" {
			allSkipped = false
		}
	}
	switch {
	case failed:
		return "failed"
	case allSkipped:
		return "skipped"
	default:
		return "passed"
	}
}

func applicable(c Control, standard string) bool {
	return standard == "" || standard == "all" || tagStr(c, standard) != ""
}

func inLevel(c Control, standard, level string) bool {
	if level == "" || level == "all" {
		return true
	}
	order, ok := levelOrder[standard]
	if !ok {
		return true
	}
	cl := tagStr(c, "level_"+strings.ReplaceAll(standard, "-", "_"))
	if cl == "" {
		return true // no tagged level = no constraint (included, as at runtime)
	}
	return indexOf(order, cl) <= indexOf(order, level)
}

func indexOf(s []string, v string) int {
	for i, x := range s {
		if x == v {
			return i
		}
	}
	return len(s)
}

// Result aggregates the (standard+level) view of a report.
type Result struct {
	Findings  []finding.Finding
	Summary   scoring.Summary
	Passed    int
	Total     int // evaluated controls (pass+fail) in the view
	Qualified int // runtime-only PASS: active proven, persistence NOT verified (subset of Passed)
	// A waived or N/A control leaves the denominator, so the grade RISES when you add one.
	// Reporting the grade without these two numbers would let anyone fabricate an A by waiving
	// what fails. They are part of the verdict, not a footnote.
	Waived        int // accepted risks: run: false in the profile's waivers.yml, with a justification
	NotApplicable int // skipped by an only_if guard (no SSSD domain, no wireless card, no GRUB...)
	OS            string
}

// Proves derives what a PASS establishes from the control's evidence type:
// [active, persistent, survives-reboot] as "yes" (proven) / "unknown" (not measured) / "na".
// This is the qualified verdict surfaced on the fiche, in the report and in OSCAL. (Single source:
// oscal.go relies on it.)
func Proves(evidence string) [3]string {
	switch evidence {
	case "effective-runtime", "behavioral":
		return [3]string{"yes", "unknown", "unknown"}
	case "persistent-config":
		return [3]string{"unknown", "yes", "yes"}
	case "inventory-state", "filesystem-state":
		return [3]string{"yes", "yes", "yes"}
	default: // manual / unclassified
		return [3]string{"na", "na", "na"}
	}
}

// FullPass indicates whether a PASS on this evidence type demonstrates a DURABLE state (survives reboot).
// A runtime-only PASS (effective-runtime / behavioral) does not demonstrate it: it proves the
// value is active now, not that it survives a restart: a "qualified" PASS.
func FullPass(evidence string) bool {
	return Proves(evidence)[2] == "yes"
}

// fullPassFor decides whether a PASS counts as FULL, from the reboot tag (persistence axis,
// authoritative), falling back on the evidence type when the tag is absent (old reports).
// A live control (reboot != yes) becomes full again if a persistent COMPANION control also
// passes (companion-aware): we have then proven both the active state AND the persistence.
func fullPassFor(reboot, evidence, companion string, passed map[string]bool) bool {
	self := false
	switch reboot {
	case "yes":
		self = true
	case "no", "unknown":
		self = false
	default:
		self = FullPass(evidence) // no reboot tag -> derived from evidence type (legacy)
	}
	if self {
		return true
	}
	return companion != "" && passed[companion] // persistence proven by the companion
}

// Evaluate filters by (standard, level) and produces the findings (= failures).
func Evaluate(r *Report, subject, standard, level string) Result {
	// Pre-pass: the set of controls that PASS (all views), to resolve the
	// persistent companions (companion-aware) independently of the standard/level filter.
	passedSet := map[string]bool{}
	for _, p := range r.Profiles {
		for _, c := range p.Controls {
			if status(c) == "passed" {
				passedSet[c.ID] = true
			}
		}
	}

	var fs []finding.Finding
	passed, scored, qualified, waived, na := 0, 0, 0, 0, 0
	for _, p := range r.Profiles {
		for _, c := range p.Controls {
			if !applicable(c, standard) || !inLevel(c, standard, level) {
				continue
			}
			st := status(c)
			if st == "passed" {
				passed++
				scored++
				if !fullPassFor(tagStr(c, "reboot"), tagStr(c, "evidence"), tagStr(c, "companion"), passedSet) {
					qualified++ // runtime-only PASS without persistent companion: persistence not proven
				}
				continue
			}
			if st != "failed" {
				// Skipped: either an ACCEPTED RISK (waived, with a justification) or genuinely
				// N/A (an only_if guard). Both leave the denominator, so both must be reported.
				if c.WaiverData.Justification != "" {
					waived++
				} else {
					na++
				}
				continue
			}
			scored++
			fs = append(fs, toFinding(c, subject, standard))
		}
	}
	sort.SliceStable(fs, func(i, j int) bool {
		ri, rj := finding.SeverityRank(fs[i].Severity), finding.SeverityRank(fs[j].Severity)
		if ri != rj {
			return ri < rj
		}
		return fs[i].Code < fs[j].Code
	})
	os := strings.TrimSpace(r.Platform.Name + " " + r.Platform.Release)
	return Result{
		Findings: fs, Summary: scoring.Summarize(fs), Passed: passed, Total: scored,
		Qualified: qualified, Waived: waived, NotApplicable: na, OS: os,
	}
}

func toFinding(c Control, subject, standard string) finding.Finding {
	var msgs []string
	for _, r := range c.Results {
		if r.Status == "failed" {
			m := r.Message
			if m == "" {
				m = r.CodeDesc
			}
			if m != "" {
				msgs = append(msgs, strings.TrimSpace(strings.SplitN(m, "\n", 2)[0]))
			}
		}
	}
	labels := map[string]string{}
	if d := tagStr(c, "domain"); d != "" {
		labels["domain"] = d
	}
	for _, k := range normKeys {
		if v := tagStr(c, k); v != "" {
			labels[k] = v
		}
	}
	if standard != "" && standard != "all" {
		if lv := tagStr(c, "level_"+strings.ReplaceAll(standard, "-", "_")); lv != "" {
			labels["level"] = lv
		}
	}
	if s := tagStr(c, "ssg"); s != "" {
		labels["ssg"] = s
	}
	if e := tagStr(c, "evidence"); e != "" {
		labels["evidence"] = e
	}
	title := c.Title
	if title == "" {
		title = c.ID
	}
	msg := strings.Join(msgs, " ; ")
	if msg == "" {
		msg = title
	}
	return finding.Finding{
		Code:        c.ID,
		Title:       title,
		Severity:    severity(c.Impact),
		Subject:     subject,
		Message:     msg,
		Remediation: strings.TrimSpace(c.Desc),
		Labels:      labels,
	}
}

// Grade: A->E grade. We start from 100 and subtract weight x number of failures per
// severity, capped. Standards' actual scale: 3 levels (high/medium/low).
func Grade(sum scoring.Summary) (letter string, points int) {
	w := map[string]float64{"critical": 25, "high": 15, "medium": 6, "low": 3}
	cap := map[string]float64{"critical": math.Inf(1), "high": 60, "medium": 20, "low": 10}
	loss := 0.0
	for sev, weight := range w {
		loss += math.Min(weight*float64(sum.Counts[sev]), cap[sev])
	}
	pts := int(math.Max(0, math.Round(100-loss)))
	if sum.Counts["critical"] > 0 && pts > 30 {
		pts = 30 // >= 1 Critical -> capped in band E (risk penalty)
	}
	switch {
	case pts >= 90:
		return "A", pts
	case pts >= 71:
		return "B", pts
	case pts >= 51:
		return "C", pts
	case pts >= 31:
		return "D", pts
	default:
		return "E", pts
	}
}

// GradeResult applies the qualified-verdict policy ON TOP of the points-based grade: a grade
// cannot be a clean "A" if the compliant controls rest on runtime-only evidence
// whose persistence is not proven. Such a grade is capped at "B" and marked
// runtime-qualified. The points (driven by failures) do not change: only the letter.
func GradeResult(res Result) (letter string, points int, runtimeQualified bool) {
	letter, points = Grade(res.Summary)
	runtimeQualified = res.Qualified > 0
	if runtimeQualified && letter == "A" {
		letter = "B" // an A is not earned on runtime-only PASS with unproven persistence
	}
	return
}

// RemediationClass classifies a control by the NATURE of its remediation, to distinguish what
// is fixable on a running host from what is not. Derived from the
// report tags (domain, evidence type, id):
//   - kernel-build: requires a recompiled kernel (kconfig-*, "Kernel build" domain)
//   - install-time: requires an architecture/partitioning decision (mount-point
//     separation, "Mounts" domain, partition-* ids)
//   - dangerous   : high operational-risk remediation (module lockdown, GRUB
//     password, iommu=force): never apply without a plan + snapshot + reboot test
//   - manual      : no automatic remediation ("manual" evidence)
//   - auto        : automatically remediable (the rest)
//
// RemediationClass reads the class off the RULE. It used to be a hardcoded list of id prefixes
// here in Go while the knowledge already lived in the YAML (`danger:`, `domain`) — two sources of
// truth, and they had already drifted: nine rhel10 controls carried `danger:` but the Go list knew
// only three of them, so six high-risk remediations were reported as plain `auto`. The engine does
// not decide what a rule is; the rule says it (see docs/reference/rules.yml `remediation_class`).
// The fallbacks below only cover a corpus rendered before the tag existed.
func RemediationClass(c Control) string {
	if k := tagStr(c, "remediation_class"); k != "" {
		return k
	}
	switch {
	case strings.EqualFold(tagStr(c, "domain"), "Kernel build"):
		return "kernel-build"
	case strings.EqualFold(tagStr(c, "domain"), "Mounts"), strings.HasPrefix(c.ID, "partition-"):
		return "install-time"
	case tagStr(c, "danger") != "":
		return "dangerous"
	case tagStr(c, "evidence") == "manual":
		return "manual"
	default:
		return "auto"
	}
}

// ClassStat aggregates the evaluated controls of a remediation class.
type ClassStat struct {
	Class  string `json:"class"`
	Passed int    `json:"passed"`
	Failed int    `json:"failed"`
	Total  int    `json:"total"`
	Grade  string `json:"grade"` // A->E grade computed on the class's controls only
}

// Posture is the breakdown by remediation class + the REMEDIABLE grade: the grade
// recomputed on the controls fixable on a live host only (excluding kernel-build and
// install-time), so that a non-fixable architecture/kernel does not mask the
// posture actually reachable. This is the answer to "why does my C include choices
// I cannot fix without reinstalling?" (ChatGPT review, sections 3-5).
type Posture struct {
	Classes          []ClassStat `json:"classes"`
	RemediableGrade  string      `json:"remediable_grade"`
	RemediablePoints int         `json:"remediable_points"`
	RemediablePassed int         `json:"remediable_passed"`
	RemediableTotal  int         `json:"remediable_total"`
}

// classOrder sets the display order of the classes.
var classOrder = []string{"auto", "manual", "dangerous", "install-time", "kernel-build"}

// Breakdown computes the breakdown by class and the remediable grade, for the same view
// (standard, level) as Evaluate.
func Breakdown(r *Report, standard, level string) Posture {
	stat := map[string]*ClassStat{}
	for _, k := range classOrder {
		stat[k] = &ClassStat{Class: k}
	}
	var remFindings []finding.Finding
	clsFindings := map[string][]finding.Finding{} // failures per class, for the per-class grade
	remPassed, remTotal := 0, 0
	for _, p := range r.Profiles {
		for _, c := range p.Controls {
			if !applicable(c, standard) || !inLevel(c, standard, level) {
				continue
			}
			st := status(c)
			if st != "passed" && st != "failed" {
				continue
			}
			cls := RemediationClass(c)
			s, ok := stat[cls]
			if !ok {
				s = &ClassStat{Class: cls}
				stat[cls] = s
			}
			s.Total++
			if st == "passed" {
				s.Passed++
			} else {
				s.Failed++
				clsFindings[cls] = append(clsFindings[cls], toFinding(c, "", standard))
			}
			if cls != "install-time" && cls != "kernel-build" { // remediable scope
				remTotal++
				if st == "passed" {
					remPassed++
				} else {
					remFindings = append(remFindings, toFinding(c, "", standard))
				}
			}
		}
	}
	remLetter, remPts := Grade(scoring.Summarize(remFindings))
	var classes []ClassStat
	for _, k := range classOrder {
		if stat[k].Total > 0 {
			stat[k].Grade, _ = Grade(scoring.Summarize(clsFindings[k]))
			classes = append(classes, *stat[k])
		}
	}
	return Posture{
		Classes: classes, RemediableGrade: remLetter, RemediablePoints: remPts,
		RemediablePassed: remPassed, RemediableTotal: remTotal,
	}
}

// Headline builds the strong summary line (grade + points + failures).
func Headline(res Result) string {
	letter, pts, rq := GradeResult(res)
	c := res.Summary.Counts
	q := ""
	if rq {
		q = fmt.Sprintf(" · runtime-qualified (%d runtime-only PASS, persistence not verified)", res.Qualified)
	}
	return fmt.Sprintf("Grade %s  (%d/100)  —  Critical %d · High %d · Medium %d · Low %d  ·  %d/%d compliant%s",
		letter, pts, c["critical"], c["high"], c["medium"], c["low"], res.Passed, res.Total, q)
}
