// Package audit traduit un rapport JSON CINC/InSpec en findings scankit, filtre
// par norme + niveau, et calcule la note A->E (modèle Plumber : perte selon le
// NOMBRE d'échecs par sévérité, malus critique).
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

// Report est la structure (partielle) du rapport JSON d'InSpec.
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

// Control est un contrôle InSpec et ses résultats.
type Control struct {
	ID      string           `json:"id"`
	Title   string           `json:"title"`
	Desc    string           `json:"desc"`
	Impact  float64          `json:"impact"`
	Tags    map[string]any   `json:"tags"`
	Refs    []map[string]any `json:"refs"`
	Results []struct {
		Status      string `json:"status"`
		CodeDesc    string `json:"code_desc"`
		Message     string `json:"message"`
		SkipMessage string `json:"skip_message"`
	} `json:"results"`
}

// normKeys : normes reconnues (ordre d'affichage). Le niveau est porté par
// level_<norme> (ex. level_bp28, level_cis).
var normKeys = []string{"bp28", "cis", "pci-dss", "nist", "stig"}

var levelOrder = map[string][]string{
	"bp28": {"minimal", "intermediary", "enhanced", "high"},
	"cis":  {"1", "2"},
}

// Load lit et décode un rapport JSON InSpec.
func Load(path string) (*Report, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var r Report
	if err := json.Unmarshal(b, &r); err != nil {
		return nil, fmt.Errorf("JSON InSpec illisible: %w", err)
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

// severity : échelle réelle des normes (3 niveaux). Le SSG ne classe pas en
// « critical » et les normes ne surchargent pas la sévérité.
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
		return true // pas de niveau tagué = pas de contrainte (inclus, comme à l'exécution)
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

// Result agrège la vue (norme+niveau) d'un rapport.
type Result struct {
	Findings  []finding.Finding
	Summary   scoring.Summary
	Passed    int
	Total     int // contrôles évalués (pass+fail) de la vue
	Qualified int // PASS runtime-only : actif prouvé, persistance NON vérifiée (sous-ensemble de Passed)
	OS        string
}

// Proves dérive ce qu'un PASS établit à partir du type de preuve du contrôle :
// [actif, persistant, survit-au-reboot] en "yes" (prouvé) / "unknown" (non mesuré) / "na".
// C'est le verdict qualifié surfacé sur la fiche, dans le rapport et en OSCAL. (Source unique :
// oscal.go s'appuie dessus.)
func Proves(evidence string) [3]string {
	switch evidence {
	case "effective-runtime", "behavioral":
		return [3]string{"yes", "unknown", "unknown"}
	case "persistent-config":
		return [3]string{"unknown", "yes", "yes"}
	case "inventory-state", "filesystem-state":
		return [3]string{"yes", "yes", "yes"}
	default: // manual / non classé
		return [3]string{"na", "na", "na"}
	}
}

// FullPass indique si un PASS sur ce type de preuve démontre un état DURABLE (survit au reboot).
// Un PASS runtime-only (effective-runtime / behavioral) ne le démontre pas : il prouve que la
// valeur est active maintenant, pas qu'elle survit à un redémarrage — un PASS « qualifié ».
func FullPass(evidence string) bool {
	return Proves(evidence)[2] == "yes"
}

// fullPassFor tranche si un PASS compte comme PLEIN, à partir du tag reboot (axe persistance,
// autoritaire) en se rabattant sur le type de preuve quand le tag est absent (vieux rapports).
// Un contrôle live (reboot != yes) redevient plein si un contrôle COMPAGNON persistant passe
// aussi (companion-aware) : on a alors prouvé l'actif ET la persistance.
func fullPassFor(reboot, evidence, companion string, passed map[string]bool) bool {
	self := false
	switch reboot {
	case "yes":
		self = true
	case "no", "unknown":
		self = false
	default:
		self = FullPass(evidence) // pas de tag reboot -> dérivé du type de preuve (legacy)
	}
	if self {
		return true
	}
	return companion != "" && passed[companion] // persistance prouvée par le compagnon
}

// Evaluate filtre par (standard, level) et produit les findings (= échecs).
func Evaluate(r *Report, subject, standard, level string) Result {
	// Pré-passe : l'ensemble des contrôles qui PASSENT (toutes vues), pour résoudre les
	// compagnons persistants (companion-aware) indépendamment du filtre norme/niveau.
	passedSet := map[string]bool{}
	for _, p := range r.Profiles {
		for _, c := range p.Controls {
			if status(c) == "passed" {
				passedSet[c.ID] = true
			}
		}
	}

	var fs []finding.Finding
	passed, scored, qualified := 0, 0, 0
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
					qualified++ // PASS runtime-only sans compagnon persistant : persistance non prouvée
				}
				continue
			}
			if st != "failed" {
				continue // N/A : pas un finding
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
	return Result{Findings: fs, Summary: scoring.Summarize(fs), Passed: passed, Total: scored, Qualified: qualified, OS: os}
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
			labels["niveau"] = lv
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

// Grade : note A->E. On part de 100 et on retranche poids x nombre d'échecs par
// sévérité, plafonné. Échelle réelle des normes : 3 niveaux (high/medium/low).
func Grade(sum scoring.Summary) (letter string, points int) {
	w := map[string]float64{"critical": 25, "high": 15, "medium": 6, "low": 3}
	cap := map[string]float64{"critical": math.Inf(1), "high": 60, "medium": 20, "low": 10}
	loss := 0.0
	for sev, weight := range w {
		loss += math.Min(weight*float64(sum.Counts[sev]), cap[sev])
	}
	pts := int(math.Max(0, math.Round(100-loss)))
	if sum.Counts["critical"] > 0 && pts > 30 {
		pts = 30 // ≥ 1 Critical -> plafonné en bande E (malus de risque)
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

// GradeResult applique la politique du verdict qualifié PAR-DESSUS la note en points : une note
// ne peut pas être un « A » net si les contrôles conformes reposent sur des preuves runtime-only
// dont la persistance n'est pas prouvée. Une telle note est plafonnée en « B » et marquée
// runtime-qualifiée. Les points (pilotés par les échecs) ne changent pas — seule la lettre.
func GradeResult(res Result) (letter string, points int, runtimeQualified bool) {
	letter, points = Grade(res.Summary)
	runtimeQualified = res.Qualified > 0
	if runtimeQualified && letter == "A" {
		letter = "B" // un A ne se gagne pas sur des PASS runtime-only à persistance non prouvée
	}
	return
}

// RemediationClass classe un contrôle par la NATURE de sa remédiation, pour distinguer ce
// qui est corrigeable sur un hôte en cours d'exécution de ce qui ne l'est pas. Dérivé des
// tags du rapport (domaine, type de preuve, id) :
//   - kernel-build : exige un noyau recompilé (kconfig-*, domaine « Kernel build »)
//   - install-time : exige une décision d'architecture/partitionnement (séparation de
//     points de montage, domaine « Mounts », ids partition-*)
//   - dangerous    : remédiation à fort risque opérationnel (verrou de modules, mot de
//     passe GRUB, iommu=force) : jamais à appliquer sans plan + snapshot + test de reboot
//   - manual       : pas de remédiation automatique (preuve « manual »)
//   - auto         : remédiable automatiquement (le reste)
func RemediationClass(c Control) string {
	id := c.ID
	switch {
	case id == "kmod-loading-disabled",
		strings.Contains(id, "modules-disabled"),
		strings.HasPrefix(id, "cmdline-iommu"),
		strings.Contains(id, "grub-password"):
		return "dangerous"
	case strings.EqualFold(tagStr(c, "domain"), "Kernel build"):
		return "kernel-build"
	case strings.EqualFold(tagStr(c, "domain"), "Mounts"), strings.HasPrefix(id, "partition-"):
		return "install-time"
	case tagStr(c, "evidence") == "manual":
		return "manual"
	default:
		return "auto"
	}
}

// ClassStat agrège les contrôles évalués d'une classe de remédiation.
type ClassStat struct {
	Class  string `json:"class"`
	Passed int    `json:"passed"`
	Failed int    `json:"failed"`
	Total  int    `json:"total"`
	Grade  string `json:"grade"` // note A->E calculée sur les seuls contrôles de la classe
}

// Posture est la ventilation par classe de remédiation + la note REMÉDIABLE : la note
// recalculée sur les seuls contrôles corrigeables sur un hôte vivant (hors kernel-build et
// install-time), pour qu'une architecture/un noyau non corrigeables ne masquent pas la
// posture réellement atteignable. C'est la réponse à « pourquoi mon C inclut-il des choix
// que je ne peux pas corriger sans réinstaller ? » (revue ChatGPT, sections 3-5).
type Posture struct {
	Classes          []ClassStat `json:"classes"`
	RemediableGrade  string      `json:"remediable_grade"`
	RemediablePoints int         `json:"remediable_points"`
	RemediablePassed int         `json:"remediable_passed"`
	RemediableTotal  int         `json:"remediable_total"`
}

// classOrder fixe l'ordre d'affichage des classes.
var classOrder = []string{"auto", "manual", "dangerous", "install-time", "kernel-build"}

// Breakdown calcule la ventilation par classe et la note remédiable, pour la même vue
// (standard, level) qu'Evaluate.
func Breakdown(r *Report, standard, level string) Posture {
	stat := map[string]*ClassStat{}
	for _, k := range classOrder {
		stat[k] = &ClassStat{Class: k}
	}
	var remFindings []finding.Finding
	clsFindings := map[string][]finding.Finding{} // échecs par classe, pour la note par classe
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
			if cls != "install-time" && cls != "kernel-build" { // périmètre remédiable
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

// Headline construit la ligne de synthèse forte (note + points + échecs).
func Headline(res Result) string {
	letter, pts, rq := GradeResult(res)
	c := res.Summary.Counts
	q := ""
	if rq {
		q = fmt.Sprintf(" · runtime-qualifiée (%d PASS runtime-only, persistance non vérifiée)", res.Qualified)
	}
	return fmt.Sprintf("Note %s  (%d/100)  —  Critical %d · High %d · Medium %d · Low %d  ·  %d/%d conformes%s",
		letter, pts, c["critical"], c["high"], c["medium"], c["low"], res.Passed, res.Total, q)
}
