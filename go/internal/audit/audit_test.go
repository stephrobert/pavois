package audit

import (
	"testing"

	"github.com/stephrobert/scankit/scoring"
)

// TestGrade freezes the A->E grade model (Plumber, 3 levels): we start from 100,
// subtract weight x failures per severity (high 15/cap 60, medium 6/20,
// low 3/10), bands A>=90 B>=71 C>=51 D>=31 else E. A change of scale
// breaks this test (and must stay in sync with the JS: cf. tools/validate_grade.py).
func TestGrade(t *testing.T) {
	cases := []struct {
		name                 string
		crit, high, med, low int
		wantLetter           string
		wantPoints           int
	}{
		{"perfect", 0, 0, 0, 0, "A", 100},
		{"one high", 0, 1, 0, 0, "B", 85},
		{"two highs (C edge)", 0, 2, 0, 0, "C", 70},
		{"high cap", 0, 5, 0, 0, "D", 40},                      // min(75,60)=60 -> 40
		{"medium capped", 0, 0, 10, 0, "B", 80},                // min(60,20)=20 -> 80
		{"low capped", 0, 0, 0, 10, "A", 90},                   // min(30,10)=10 -> 90
		{"everything down", 0, 10, 10, 10, "E", 10},            // 60+20+10=90 -> 10
		{"one critical -> E penalty", 1, 0, 0, 0, "E", 30},     // 100-25=75, penalty -> 30
		{"critical + high, penalty caps", 1, 1, 0, 0, "E", 30}, // 100-40=60, penalty -> 30
		{"heavy critical", 2, 3, 0, 0, "E", 5},                 // 50+45=95 -> 5 (already < 30)
	}
	for _, c := range cases {
		sum := scoring.Summary{Counts: map[string]int{
			"critical": c.crit, "high": c.high, "medium": c.med, "low": c.low,
		}}
		letter, pts := Grade(sum)
		if letter != c.wantLetter || pts != c.wantPoints {
			t.Errorf("%s: Grade = %s/%d, want %s/%d",
				c.name, letter, pts, c.wantLetter, c.wantPoints)
		}
	}
}

// TestProves freezes the derivation of the qualified verdict by evidence type (single source,
// shared by the engine, the fiche and the OSCAL export).
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
			t.Errorf("Proves(%q) = %v, want %v", c.evidence, got, c.want)
		}
		if got := FullPass(c.evidence); got != c.full {
			t.Errorf("FullPass(%q) = %v, want %v", c.evidence, got, c.full)
		}
	}
}

// TestFullPassFor freezes the companion-aware policy: the reboot tag takes precedence (yes->full,
// no/unknown->qualified), otherwise we derive from the evidence type; a live control becomes
// full again if its persistent companion passes.
func TestFullPassFor(t *testing.T) {
	passed := map[string]bool{"sysctl-x-persisted": true}
	cases := []struct {
		reboot, evidence, companion string
		want                        bool
	}{
		{"yes", "effective-runtime", "", true},                  // self-proving (kconfig, sshd -T)
		{"no", "effective-runtime", "", false},                  // live, without companion -> qualified
		{"no", "effective-runtime", "sysctl-x-persisted", true}, // persistent companion passes -> full
		{"no", "effective-runtime", "absent-companion", false},  // companion absent/fails -> qualified
		{"unknown", "manual", "", false},
		{"", "persistent-config", "", true},  // no reboot tag -> derived from evidence type (legacy)
		{"", "effective-runtime", "", false}, // legacy runtime -> qualified
	}
	for _, c := range cases {
		if got := fullPassFor(c.reboot, c.evidence, c.companion, passed); got != c.want {
			t.Errorf("fullPassFor(%q,%q,%q) = %v, want %v", c.reboot, c.evidence, c.companion, got, c.want)
		}
	}
}

// TestGradeResult freezes the "cap + qualifier" policy: the points do not move,
// but an A resting on runtime-only PASS (unproven persistence) is capped at B and
// marked runtime-qualified. Below A, the letter is unchanged (the qualifier stays displayed).
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
		{"clean A (persistent evidence only)", mk(0, 0, 0), "A", false},
		{"A capped -> B (runtime-only PASS)", mk(0, 0, 12), "B", true},
		{"B stays B + qualified", mk(0, 1, 5), "B", true},
		{"E stays E + qualified", mk(1, 0, 3), "E", true},
	}
	for _, c := range cases {
		letter, _, rq := GradeResult(c.res)
		if letter != c.wantLetter || rq != c.wantRQ {
			t.Errorf("%s: GradeResult = %s/rq=%v, want %s/rq=%v",
				c.name, letter, rq, c.wantLetter, c.wantRQ)
		}
	}
}
