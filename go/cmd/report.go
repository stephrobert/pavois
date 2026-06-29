package cmd

import (
	"fmt"
	"io"

	"github.com/charmbracelet/lipgloss"

	"github.com/stephrobert/scankit/finding"
	screport "github.com/stephrobert/scankit/report"

	"pavois/internal/audit"
)

// gradeArt : grande lettre A→E (style ANSI Shadow) pour la carte de score.
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

// writeScorecard rend la note A→E en GROSSE LETTRE colorée (comme pitstop/plumber)
// + points + bande, à côté de la lettre.
func writeScorecard(w io.Writer, letter string, points, passed, total, qualified int) {
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
		info[4] = mut.Render(fmt.Sprintf("%d runtime-only pass(es) — persistence unproven", qualified))
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

// writePosture rend la ventilation par classe de remédiation + la note remédiable, pour
// montrer ce qui est corrigeable sur un hôte vivant vs l'architecture / le noyau.
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
		line := fmt.Sprintf("    %-13s %d/%d passing", c.Class, c.Passed, c.Total)
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

// onlySeverities filtre les findings sur un jeu de sévérités (terminal concis :
// on n'affiche que critical/high, le reste va au rapport HTML).
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

// pavoisBanner : wordmark « PAVOIS » en GROSSES LETTRES (style ANSI Shadow),
// le même style que la lettre de note A→E affichée en fin de scan.
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

// bannerOpts : options minimales pour le bandeau (logo + version + tagline),
// affiché dès le lancement de la CLI (tout sous-commande).
func bannerOpts() screport.Options {
	return screport.Options{
		ToolName: "pavois",
		Version:  version,
		Banner:   pavoisBanner(),
		Tagline:  "Effective Linux Compliance (CINC/InSpec) · grade A-E",
		Brand:    lipgloss.Color("#dc2626"),
	}
}

// reportOptions : présentation scankit pour le scan (bandeau + tier domaine).
func reportOptions(_ /*version*/, mode, source, headline string) screport.Options {
	o := bannerOpts()
	o.Mode = mode
	o.Source = source
	o.HideTable = true // la table fait doublon avec les blocs détail
	o.SummaryHeadline = headline
	o.TierOf = func(f finding.Finding) string {
		if d := f.Label("domain"); d != "" {
			return d
		}
		return f.Label("niveau")
	}
	return o
}
