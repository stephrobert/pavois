package render

import (
	"fmt"
	"html"
	"strings"
)

// CampItem is one control in a campaign delta section.
type CampItem struct{ ID, Title, Domain, Sev string }

// CampSection groups controls that share a transition (e.g. "fixed", "regressed").
type CampSection struct {
	Label string // human label, e.g. "Fixed (failed -> passed)"
	Hint  string // one-line explanation
	Items []CampItem
	Bad   bool // highlight in red (regressions / newly-failing)
	Open  bool // render the <details> expanded
}

// CampRow is one line of the transition matrix (the "scope delta" table).
type CampRow struct {
	Label string
	Count int
	Kind  string // "good" | "bad" | "neutral"
}

// CampaignData is everything Campaign needs: the before/after summary and the
// per-transition breakdown. The cmd layer computes it; this file only renders.
type CampaignData struct {
	BeforeLabel, AfterLabel string
	BeforeGrade, AfterGrade string
	BeforePass, BeforeTotal int
	AfterPass, AfterTotal   int
	Generated               string
	Rows                    []CampRow
	Sections                []CampSection
}

// Campaign renders a self-contained before/after hardening campaign report: the
// grade delta, the transition matrix (what ChatGPT called the "scope delta", so a
// reviewer cannot dismiss the result as "you changed the denominator mid-way"), and
// the per-transition control lists. Reuses the scan report stylesheet for one look.
func Campaign(d CampaignData) string {
	var b strings.Builder
	esc := html.EscapeString
	b.WriteString("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">")
	b.WriteString("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
	b.WriteString("<title>Pavois hardening campaign</title><style>\n")
	b.WriteString(cssAsset)
	b.WriteString(campaignCSS)
	b.WriteString("\n</style></head><body><main class=\"camp\">\n")

	b.WriteString("<h1>Hardening campaign</h1>\n")
	if d.Generated != "" {
		fmt.Fprintf(&b, "<p class=\"camp-gen\">Generated %s</p>\n", esc(d.Generated))
	}

	// Grade delta header: before -> after.
	b.WriteString("<section class=\"camp-delta\">\n")
	gradeCard := func(role, label, grade string, pass, total int) {
		pct := 0
		if total > 0 {
			pct = pass * 100 / total
		}
		fmt.Fprintf(&b, "<div class=\"gcard %s\"><span class=\"grole\">%s</span>"+
			"<span class=\"gbig grade-%s\">%s</span>"+
			"<span class=\"gmeta\">%d/%d passing (%d%%)</span>"+
			"<span class=\"gsrc\">%s</span></div>\n",
			role, role, esc(strings.ToLower(grade)), esc(grade), pass, total, pct, esc(label))
	}
	gradeCard("before", d.BeforeLabel, d.BeforeGrade, d.BeforePass, d.BeforeTotal)
	b.WriteString("<div class=\"garrow\">&rarr;</div>\n")
	gradeCard("after", d.AfterLabel, d.AfterGrade, d.AfterPass, d.AfterTotal)
	b.WriteString("</section>\n")

	// Regressions banner: the risk signal, surfaced at the very top in red so it is the first
	// thing a reviewer sees, not buried in the matrix (ChatGPT review, section 4).
	for _, s := range d.Sections {
		if !s.Bad || len(s.Items) == 0 {
			continue
		}
		fmt.Fprintf(&b, "<section class=\"camp-regress\"><h2>&#9888; %s</h2>\n", esc(s.Label))
		b.WriteString("<p>Compliant before, broken after. Triage each: a remediation bug, an acceptable trade-off, or a gap to fix.</p>\n<ul>\n")
		for _, it := range s.Items {
			t := it.Title
			if t == "" {
				t = it.ID
			}
			fmt.Fprintf(&b, "<li><span class=\"cid\">%s</span> %s</li>\n", esc(it.ID), esc(t))
		}
		b.WriteString("</ul></section>\n")
		break
	}

	// Transition matrix.
	b.WriteString("<h2>Scope delta</h2>\n")
	b.WriteString("<p class=\"camp-note\">Every control's state before and after. ")
	b.WriteString("The applicable set can grow when the baseline installs components ")
	b.WriteString("(auditd, AIDE...), so compare transitions, not raw pass rates.</p>\n")
	b.WriteString("<table class=\"camp-matrix\"><thead><tr><th>Transition</th><th>Controls</th></tr></thead><tbody>\n")
	for _, r := range d.Rows {
		fmt.Fprintf(&b, "<tr class=\"k-%s\"><td>%s</td><td class=\"num\">%d</td></tr>\n",
			esc(r.Kind), esc(r.Label), r.Count)
	}
	b.WriteString("</tbody></table>\n")

	// Per-transition control lists (the Bad/regressions section is already in the top banner).
	for _, s := range d.Sections {
		if len(s.Items) == 0 || s.Bad {
			continue
		}
		cls := "camp-sec"
		openAttr := ""
		if s.Open {
			openAttr = " open"
		}
		fmt.Fprintf(&b, "<details class=\"%s\"%s><summary>%s <span class=\"cnt\">%d</span></summary>\n",
			cls, openAttr, esc(s.Label), len(s.Items))
		if s.Hint != "" {
			fmt.Fprintf(&b, "<p class=\"camp-hint\">%s</p>\n", esc(s.Hint))
		}
		b.WriteString("<table class=\"camp-list\"><tbody>\n")
		for _, it := range s.Items {
			title := it.Title
			if title == "" {
				title = it.ID
			}
			sev := it.Sev
			if sev == "" {
				sev = "-"
			}
			dom := it.Domain
			if dom == "" {
				dom = "-"
			}
			fmt.Fprintf(&b, "<tr><td class=\"sev sev-%s\">%s</td><td class=\"cid\">%s</td>"+
				"<td class=\"ctitle\">%s</td><td class=\"cdom\">%s</td></tr>\n",
				esc(strings.ToLower(sev)), esc(sev), esc(it.ID), esc(title), esc(dom))
		}
		b.WriteString("</tbody></table></details>\n")
	}

	b.WriteString("</main></body></html>\n")
	return b.String()
}

const campaignCSS = `
.camp{max-width:980px;margin:0 auto;padding:2rem 1.25rem}
.camp h1{margin:0 0 .25rem}
.camp-regress{border:2px solid #dc2626;background:#fef2f2;border-radius:12px;padding:1rem 1.25rem;margin:0 0 2rem}
.camp-regress h2{margin:.1rem 0 .4rem;color:#b91c1c}
.camp-regress ul{margin:.3rem 0 0;padding-left:1.2rem}
.camp-regress li{margin:.2rem 0}
.camp-regress .cid{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em}
.camp-gen{color:#6b7280;font-size:.85rem;margin:0 0 1.5rem}
.camp-delta{display:flex;align-items:stretch;gap:1rem;margin:1rem 0 2rem;flex-wrap:wrap}
.gcard{flex:1 1 220px;display:flex;flex-direction:column;gap:.2rem;padding:1rem 1.25rem;border:1px solid #e5e7eb;border-radius:12px;background:#fff}
.gcard.after{border-color:#c7d2fe}
.grole{text-transform:uppercase;letter-spacing:.08em;font-size:.7rem;color:#6b7280}
.gbig{font-size:2.6rem;font-weight:800;line-height:1}
.gmeta{font-weight:600}
.gsrc{color:#6b7280;font-size:.8rem;word-break:break-all}
.garrow{display:flex;align-items:center;font-size:2rem;color:#9ca3af}
.grade-a{color:#15803d}.grade-b{color:#65a30d}.grade-c{color:#ca8a04}.grade-d{color:#ea580c}.grade-e{color:#dc2626}
.camp-note,.camp-hint{color:#6b7280;font-size:.85rem;max-width:70ch}
.camp-matrix{border-collapse:collapse;width:100%;max-width:520px;margin:.5rem 0 2rem}
.camp-matrix th,.camp-matrix td{text-align:left;padding:.45rem .75rem;border-bottom:1px solid #eef0f3}
.camp-matrix td.num{text-align:right;font-variant-numeric:tabular-nums;font-weight:700}
.camp-matrix tr.k-good td{color:#15803d}
.camp-matrix tr.k-bad td{color:#dc2626}
.camp-sec{margin:.5rem 0;border:1px solid #e5e7eb;border-radius:10px;padding:.25rem .9rem}
.camp-sec.bad{border-color:#fecaca;background:#fef2f2}
.camp-sec>summary{cursor:pointer;font-weight:600;padding:.5rem 0}
.camp-sec .cnt{display:inline-block;margin-left:.4rem;padding:0 .5rem;border-radius:999px;background:#eef0f3;font-size:.8rem}
.camp-list{border-collapse:collapse;width:100%;margin:.25rem 0 .75rem}
.camp-list td{padding:.3rem .5rem;border-bottom:1px solid #f1f3f5;font-size:.9rem;vertical-align:top}
.camp-list .cid{font-family:ui-monospace,monospace;color:#374151;white-space:nowrap}
.camp-list .cdom{color:#6b7280;white-space:nowrap}
.camp-list .sev{font-size:.7rem;text-transform:uppercase;font-weight:700;white-space:nowrap}
.sev-critical{color:#dc2626}.sev-high{color:#ea580c}.sev-medium{color:#ca8a04}.sev-low{color:#6b7280}
`
