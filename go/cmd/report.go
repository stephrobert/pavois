package cmd

import (
	"fmt"
	"io"

	"github.com/charmbracelet/lipgloss"

	"github.com/stephrobert/scankit/finding"
	screport "github.com/stephrobert/scankit/report"

	"pavois/internal/audit"
)

// gradeArt: large A→E letter (ANSI Shadow style) for the scorecard.
var gradeArt = map[string][]string{
	"A": {" █████╗ ", "██╔══██╗", "███████║", "██╔══██║", "██║  ██║", "╚═╝  ╚═╝"},
	"B": {"██████╗ ", "██╔══██╗", "██████╔╝", "██╔══██╗", "██████╔╝", "╚═════╝ "},
	"C": {" ██████╗", "██╔════╝", "██║     ", "██║     ", "╚██████╗", " ╚═════╝"},
	"D": {"██████╗ ", "██╔══██╗", "██║  ██║", "██║  ██║", "██████╔╝", "╚═════╝ "},
	"E": {"███████╗", "██╔════╝", "█████╗  ", "██╔══╝  ", "███████╗", "╚══════╝"},
}

var gradeColor = map[string]lipgloss.Color{
	"A": "#16a34a", "B": "#65a30d", "C": "#ca8a04", "D": "#ea580c", "E": "#dc2626",
}

var gradeBand = map[string]string{
	"A": "Excellent", "B": "Good", "C": "Fair", "D": "Poor", "E": "Critical",
}

// writeScorecard renders the A→E grade as a BIG colored LETTER (like pitstop/plumber)
// + points + band, next to the letter.
func writeScorecard(w io.Writer, letter string, points, passed, total, qualified, waived, na int) {
	art := gradeArt[letter]
	if art == nil {
		art = gradeArt["E"]
	}
	col := lipgloss.NewStyle().Foreground(gradeColor[letter]).Bold(true)
	mut := lipgloss.NewStyle().Foreground(lipgloss.Color("#64748b"))
	band := gradeBand[letter]
	if qualified > 0 {
		band += " · runtime-qualified"
	}
	info := []string{
		"",
		lipgloss.NewStyle().Bold(true).Render(fmt.Sprintf("Grade %s", letter)) +
			"  " + mut.Render(band),
		fmt.Sprintf("%d / 100 pts", points),
		mut.Render(fmt.Sprintf("%d/%d controls passing", passed, total)),
		"", "",
	}
	if qualified > 0 {
		info[4] = mut.Render(fmt.Sprintf("%d runtime-only pass(es): persistence unproven", qualified))
	}
	// A waived or N/A control is OUT of the denominator above, so the grade RISES when you add
	// one. Reporting the grade without these two numbers would let anyone fabricate an A by
	// waiving what fails: they belong to the verdict, not to a footnote.
	if waived > 0 || na > 0 {
		info[5] = mut.Render(fmt.Sprintf("%d waived (accepted risk) · %d n/a · %d of %d evaluated",
			waived, na, total, total+waived+na))
	}
	_, _ = fmt.Fprintln(w)
	for i, line := range art {
		extra := ""
		if i < len(info) {
			extra = "   " + info[i]
		}
		_, _ = fmt.Fprintln(w, "  "+col.Render(line)+extra)
	}
	_, _ = fmt.Fprintln(w)
}

// writePosture renders the breakdown by remediation class + the remediable grade, to
// show what is fixable on a live host vs the architecture / the kernel.
func writePosture(w io.Writer, p audit.Posture) {
	if len(p.Classes) == 0 {
		return
	}
	mut := lipgloss.NewStyle().Foreground(lipgloss.Color("#64748b"))
	hints := map[string]string{
		"install-time": "architecture, e.g. a separate partition",
		"kernel-build": "needs a kernel rebuild",
		"dangerous":    "high-risk remediation",
		"manual":       "no auto-remediation",
	}
	_, _ = fmt.Fprintln(w, "  Posture by remediation class:")
	for _, c := range p.Classes {
		grade := c.Grade
		if grade == "" {
			grade = "-"
		}
		line := fmt.Sprintf("    %-13s %s  %d/%d passing", c.Class, grade, c.Passed, c.Total)
		if h := hints[c.Class]; h != "" {
			line += "  " + mut.Render("("+h+")")
		}
		_, _ = fmt.Fprintln(w, line)
	}
	_, _ = fmt.Fprintln(w, "  "+mut.Render(fmt.Sprintf(
		"Remediable posture: grade %s (%d/%d, excludes install-time + kernel-build)",
		p.RemediableGrade, p.RemediablePassed, p.RemediableTotal)))
	_, _ = fmt.Fprintln(w)
}

// onlySeverities filters findings on a set of severities (concise terminal:
// only critical/high are shown, the rest goes to the HTML report).
func onlySeverities(fs []finding.Finding, keep ...string) []finding.Finding {
	set := map[string]bool{}
	for _, s := range keep {
		set[s] = true
	}
	var out []finding.Finding
	for _, f := range fs {
		if set[f.Severity] {
			out = append(out, f)
		}
	}
	return out
}

// pavoisBanner: "PAVOIS" wordmark in BIG LETTERS (ANSI Shadow style),
// the same style as the A→E grade letter shown at the end of a scan.
func pavoisBanner() []string {
	letters := map[rune][]string{
		'P': {"██████╗ ", "██╔══██╗", "██████╔╝", "██╔═══╝ ", "██║     ", "╚═╝     "},
		'A': {" █████╗ ", "██╔══██╗", "███████║", "██╔══██║", "██║  ██║", "╚═╝  ╚═╝"},
		'V': {"██╗   ██╗", "██║   ██║", "██║   ██║", "╚██╗ ██╔╝", " ╚████╔╝ ", "  ╚═══╝  "},
		'O': {" ██████╗ ", "██╔═══██╗", "██║   ██║", "██║   ██║", "╚██████╔╝", " ╚═════╝ "},
		'I': {"██╗", "██║", "██║", "██║", "██║", "╚═╝"},
		'S': {"███████╗", "██╔════╝", "███████╗", "╚════██║", "███████║", "╚══════╝"},
	}
	lines := make([]string, 6)
	for _, r := range "PAVOIS" {
		for i := 0; i < 6; i++ {
			lines[i] += letters[r][i] + " "
		}
	}
	return lines
}

// bannerOpts: minimal options for the banner (logo + version + tagline),
// shown as soon as the CLI is launched (any subcommand).
func bannerOpts() screport.Options {
	return screport.Options{
		ToolName: "pavois",
		Version:  version,
		Banner:   pavoisBanner(),
		Tagline:  "Effective Linux Compliance (CINC/InSpec) · grade A-E",
		Brand:    lipgloss.Color("#dc2626"),
	}
}

// reportOptions: scankit presentation for the scan (banner + domain tier).
func reportOptions(_ /*version*/, mode, source, headline string) screport.Options {
	o := bannerOpts()
	o.Mode = mode
	o.Source = source
	o.HideTable = true // the table duplicates the detail blocks
	o.SummaryHeadline = headline
	o.TierOf = func(f finding.Finding) string {
		if d := f.Label("domain"); d != "" {
			return d
		}
		return f.Label("level")
	}
	return o
}
