// Package render produit le rapport HTML autoporté et MULTI-NORMES (note A->E,
// filtres, sous-chapitres). Port de pavois/render.py : le CSS et le JS
// interactifs sont EMBARQUÉS à l'identique ; seules les données changent.
package render

import (
	_ "embed"
	"encoding/json"
	"html"
	"strings"

	"pavois/internal/audit"
)

//go:embed assets/style.css
var cssAsset string

//go:embed assets/app.js
var jsAsset string

var normOrder = []string{"bp28", "cis", "pci-dss", "nist", "stig"}
var normLabels = map[string]string{
	"bp28": "ANSSI BP-028", "cis": "CIS", "pci-dss": "PCI-DSS",
	"nist": "NIST 800-171", "stig": "STIG",
}

// Meta : caractéristiques de l'évaluation pour l'en-tête.
type Meta struct{ Machine, Transport, Timestamp, Engine string }

type chk struct {
	St   string `json:"st"`
	Desc string `json:"desc"`
	Msg  string `json:"msg"`
}

type ctrl struct {
	ID        string            `json:"id"`
	Title     string            `json:"title"`
	Desc      string            `json:"desc"`
	Impact    float64           `json:"impact"`
	Sev       string            `json:"sev"`
	Status    string            `json:"status"`
	Domain    string            `json:"domain"`
	Evidence  string            `json:"evidence,omitempty"`  // type de preuve réellement collectée
	Reboot    string            `json:"reboot,omitempty"`    // reboot_survivable: yes|no|unknown (axe persistance)
	Companion string            `json:"companion,omitempty"` // contrôle persistant compagnon (companion-aware)
	Danger    string            `json:"danger,omitempty"`    // risque de brick/lockout si la remédiation est appliquée
	Norms     map[string]string `json:"norms"`
	Levels    map[string]string `json:"levels"`
	Refs      []string          `json:"refs"`
	Checks    []chk             `json:"checks"`
	Merge     string            `json:"merge,omitempty"` // frères à fusionner en vue « toutes normes »
}

func tagStr(c audit.Control, k string) string {
	if v, ok := c.Tags[k]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

func severity(impact float64) string {
	switch {
	case impact >= 0.9:
		return "critique"
	case impact >= 0.7:
		return "haute"
	case impact >= 0.4:
		return "moyenne"
	default:
		return "basse"
	}
}

func status(c audit.Control) string {
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

func domain(c audit.Control) string {
	if d := tagStr(c, "domain"); d != "" {
		return d
	}
	if s := tagStr(c, "section"); s != "" {
		return s
	}
	pref := ""
	for _, ch := range c.ID {
		if ch == '-' || ch == '_' || (ch >= '0' && ch <= '9') {
			break
		}
		pref += string(ch)
	}
	if pref == "" {
		return "Divers"
	}
	return pref
}

func controlData(c audit.Control) ctrl {
	title := c.Title
	if title == "" {
		title = c.ID
	}
	norms := map[string]string{}
	levels := map[string]string{}
	for _, k := range normOrder {
		if v := tagStr(c, k); v != "" {
			norms[k] = v
		}
		if lv := tagStr(c, "level_"+strings.ReplaceAll(k, "-", "_")); lv != "" {
			levels[k] = lv
		}
	}
	refs := []string{}
	for _, r := range c.Refs {
		if v, ok := r["ref"].(string); ok && v != "" {
			refs = append(refs, v)
		} else if v, ok := r["url"].(string); ok && v != "" {
			refs = append(refs, v)
		}
	}
	checks := []chk{}
	for _, r := range c.Results {
		msg := r.Message
		if msg == "" {
			msg = r.SkipMessage
		}
		checks = append(checks, chk{St: r.Status, Desc: r.CodeDesc, Msg: strings.TrimSpace(msg)})
	}
	return ctrl{
		ID: c.ID, Title: title, Desc: strings.TrimSpace(c.Desc),
		Impact: c.Impact, Sev: severity(c.Impact), Status: status(c),
		Domain: domain(c), Evidence: tagStr(c, "evidence"), Reboot: tagStr(c, "reboot"),
		Companion: tagStr(c, "companion"), Danger: tagStr(c, "danger"),
		Norms: norms, Levels: levels, Refs: refs, Checks: checks,
		Merge: tagStr(c, "merge_group"),
	}
}

func e(s string) string { return html.EscapeString(s) }

// HTML rend le rapport complet. Retourne (html, nbContrôles, nbNormes).
func HTML(rep *audit.Report, m Meta) (string, int, int) {
	var cdata []ctrl
	for _, p := range rep.Profiles {
		for _, c := range p.Controls {
			cdata = append(cdata, controlData(c))
		}
	}
	// normes présentes (ordre fixe)
	var present []string
	for _, n := range normOrder {
		for _, c := range cdata {
			if c.Norms[n] != "" {
				present = append(present, n)
				break
			}
		}
	}
	pname, pver := "Profil", ""
	if len(rep.Profiles) > 0 {
		if rep.Profiles[0].Title != "" {
			pname = rep.Profiles[0].Title
		}
		pver = rep.Profiles[0].Version
	}
	osStr := strings.TrimSpace(rep.Platform.Name + " " + rep.Platform.Release)
	if osStr == "" {
		osStr = "n/a"
	}
	options := `<option value="all">Toutes normes</option>`
	for _, n := range present {
		cnt := 0
		for _, c := range cdata {
			if c.Norms[n] != "" {
				cnt++
			}
		}
		options += `<option value="` + n + `">` + e(normLabels[n]) + ` (` +
			itoa(cnt) + `)</option>`
	}
	payloadB, _ := json.Marshal(cdata)
	payload := strings.ReplaceAll(string(payloadB), "</", "<\\/")
	normsB, _ := json.Marshal(present)

	var b strings.Builder
	b.WriteString(`<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rapport de conformité - ` + e(pname) + `</title>
<style>`)
	b.WriteString(cssAsset)
	b.WriteString(`</style></head><body>
<header><h1>Rapport de conformité</h1>
<div class="sub">` + e(pname) + ` ` + e(pver) + ` &middot; généré le ` + e(m.Timestamp) + ` &middot; pavois</div></header>
<div class="wrap">

<div class="card"><h2>Caractéristiques de l'évaluation</h2><div class="grid">
  <div><b>Machine</b> ` + e(m.Machine) + `</div>
  <div><b>Transport</b> ` + e(m.Transport) + `</div>
  <div><b>Horodatage</b> ` + e(m.Timestamp) + `</div>
  <div><b>Système</b> ` + e(osStr) + `</div>
  <div><b>Profil</b> ` + e(pname) + ` ` + e(pver) + `</div>
  <div><b>Moteur</b> ` + e(m.Engine) + `</div>
</div></div>

<div class="toolbar">
  <div class="tgroup">
    <label class="fld">Réglementation
      <select id="cf-std" onchange="onStd()">` + options + `</select></label>
    <label class="fld" id="cf-lvl-wrap" style="display:none">Niveau
      <select id="cf-lvl" onchange="render()"></select></label>
    <label class="fld">Sévérité min.
      <select id="cf-sev" onchange="cfApply()">
        <option value="all">Toutes</option>
        <option value="moyenne">moyenne et +</option>
        <option value="haute">haute et +</option>
        <option value="critique">critique</option>
      </select></label>
  </div>
  <input type="search" id="cf-q" class="search" oninput="cfApply()" placeholder="Rechercher une règle...">
  <div class="seg" role="group" aria-label="Filtre par résultat">
    <label><input type="radio" name="cf-res" value="all" checked onchange="cfApply()"><span>Tous</span></label>
    <label><input type="radio" name="cf-res" value="failed" onchange="cfApply()"><span>Échecs</span></label>
    <label><input type="radio" name="cf-res" value="passed" onchange="cfApply()"><span>Réussis</span></label>
    <label><input type="radio" name="cf-res" value="skipped" onchange="cfApply()"><span>N/A</span></label>
  </div>
</div>

<div class="card"><h2>Conformité et score</h2><div id="cf-score"></div></div>
<div class="card" id="cf-exec-card"><h2>Résumé exécutif</h2><div id="cf-exec"></div></div>
<div class="legend">
  <b>Deux axes distincts</b> :
  <b>Niveau</b> = palier de durcissement de la <i>réglementation choisie</i>
  (ANSSI minimal→élevé, CIS niveau&nbsp;1/2) ; <span class="lvl">pastille bleue</span>,
  cumulatif (un palier inclut les inférieurs).
  <b>Sévérité</b> = criticité du <i>contrôle</i> lui-même (impact InSpec),
  <span class="sv h">haute</span> <span class="sv m">moyenne</span> <span class="sv b">basse</span> ;
  fixe, indépendante de la norme.
  <br>Choisir une réglementation recompose chapitres et score. Cliquer une règle pour son détail.
</div>
<div id="cf-sections"></div>

<script>var CFDATA=` + payload + `;var CFNORMS=` + string(normsB) + `;</script>
<script>`)
	b.WriteString(jsAsset)
	b.WriteString(`</script>
</div></body></html>`)
	return b.String(), len(cdata), len(present)
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var d []byte
	for n > 0 {
		d = append([]byte{byte('0' + n%10)}, d...)
		n /= 10
	}
	return string(d)
}
