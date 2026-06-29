package audit

import (
	"testing"

	"github.com/stephrobert/scankit/scoring"
)

// TestGrade fige le modèle de note A->E (Plumber, 3 niveaux) : on part de 100,
// on retranche poids x échecs par sévérité (haute 15/plaf 60, moyenne 6/20,
// basse 3/10), bandes A>=90 B>=71 C>=51 D>=31 sinon E. Un changement de barème
// casse ce test (et doit rester synchrone avec le JS — cf. tools/validate_grade.py).
func TestGrade(t *testing.T) {
	cases := []struct {
		name                 string
		crit, high, med, low int
		wantLetter           string
		wantPoints           int
	}{
		{"parfait", 0, 0, 0, 0, "A", 100},
		{"une haute", 0, 1, 0, 0, "B", 85},
		{"deux hautes (bord C)", 0, 2, 0, 0, "C", 70},
		{"plafond haute", 0, 5, 0, 0, "D", 40},                    // min(75,60)=60 -> 40
		{"moyennes plafonnées", 0, 0, 10, 0, "B", 80},             // min(60,20)=20 -> 80
		{"basses plafonnées", 0, 0, 0, 10, "A", 90},               // min(30,10)=10 -> 90
		{"tout au tapis", 0, 10, 10, 10, "E", 10},                 // 60+20+10=90 -> 10
		{"un critical -> malus E", 1, 0, 0, 0, "E", 30},           // 100-25=75, malus -> 30
		{"critical + haute, malus plafonne", 1, 1, 0, 0, "E", 30}, // 100-40=60, malus -> 30
		{"critical lourd", 2, 3, 0, 0, "E", 5},                    // 50+45=95 -> 5 (déjà < 30)
	}
	for _, c := range cases {
		sum := scoring.Summary{Counts: map[string]int{
			"critical": c.crit, "high": c.high, "medium": c.med, "low": c.low,
		}}
		letter, pts := Grade(sum)
		if letter != c.wantLetter || pts != c.wantPoints {
			t.Errorf("%s: Grade = %s/%d, attendu %s/%d",
				c.name, letter, pts, c.wantLetter, c.wantPoints)
		}
	}
}

// TestProves fige la dérivation du verdict qualifié par type de preuve (source unique,
// partagée par le moteur, la fiche et l'export OSCAL).
func TestProves(t *testing.T) {
	cases := []struct {
		evidence string
		want     [3]string
		full     bool
	}{
		{"effective-runtime", [3]string{"yes", "unknown", "unknown"}, false},
		{"behavioral", [3]string{"yes", "unknown", "unknown"}, false},
		{"persistent-config", [3]string{"unknown", "yes", "yes"}, true},
		{"inventory-state", [3]string{"yes", "yes", "yes"}, true},
		{"filesystem-state", [3]string{"yes", "yes", "yes"}, true},
		{"manual", [3]string{"na", "na", "na"}, false},
		{"", [3]string{"na", "na", "na"}, false},
	}
	for _, c := range cases {
		if got := Proves(c.evidence); got != c.want {
			t.Errorf("Proves(%q) = %v, attendu %v", c.evidence, got, c.want)
		}
		if got := FullPass(c.evidence); got != c.full {
			t.Errorf("FullPass(%q) = %v, attendu %v", c.evidence, got, c.full)
		}
	}
}

// TestFullPassFor fige la politique companion-aware : le tag reboot prime (yes->plein,
// no/unknown->qualifié), à défaut on dérive du type de preuve ; un contrôle live redevient
// plein si son compagnon persistant passe.
func TestFullPassFor(t *testing.T) {
	passed := map[string]bool{"sysctl-x-persisted": true}
	cases := []struct {
		reboot, evidence, companion string
		want                        bool
	}{
		{"yes", "effective-runtime", "", true},                  // auto-prouvant (kconfig, sshd -T)
		{"no", "effective-runtime", "", false},                  // live, sans compagnon -> qualifié
		{"no", "effective-runtime", "sysctl-x-persisted", true}, // compagnon persistant passe -> plein
		{"no", "effective-runtime", "absent-companion", false},  // compagnon absent/échoue -> qualifié
		{"unknown", "manual", "", false},
		{"", "persistent-config", "", true},  // pas de tag reboot -> dérivé du type de preuve (legacy)
		{"", "effective-runtime", "", false}, // legacy runtime -> qualifié
	}
	for _, c := range cases {
		if got := fullPassFor(c.reboot, c.evidence, c.companion, passed); got != c.want {
			t.Errorf("fullPassFor(%q,%q,%q) = %v, attendu %v", c.reboot, c.evidence, c.companion, got, c.want)
		}
	}
}

// TestGradeResult fige la politique « plafond + qualificatif » : les points ne bougent pas,
// mais un A reposant sur des PASS runtime-only (persistance non prouvée) est plafonné en B et
// marqué runtime-qualifié. Sous A, la lettre est inchangée (le qualificatif reste affiché).
func TestGradeResult(t *testing.T) {
	mk := func(crit, high int, qualified int) Result {
		return Result{
			Summary:   scoring.Summary{Counts: map[string]int{"critical": crit, "high": high}},
			Qualified: qualified,
		}
	}
	cases := []struct {
		name       string
		res        Result
		wantLetter string
		wantRQ     bool
	}{
		{"A net (que des preuves persistantes)", mk(0, 0, 0), "A", false},
		{"A plafonné -> B (PASS runtime-only)", mk(0, 0, 12), "B", true},
		{"B reste B + qualifié", mk(0, 1, 5), "B", true},
		{"E reste E + qualifié", mk(1, 0, 3), "E", true},
	}
	for _, c := range cases {
		letter, _, rq := GradeResult(c.res)
		if letter != c.wantLetter || rq != c.wantRQ {
			t.Errorf("%s: GradeResult = %s/rq=%v, attendu %s/rq=%v",
				c.name, letter, rq, c.wantLetter, c.wantRQ)
		}
	}
}
