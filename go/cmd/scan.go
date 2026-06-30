package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"

	screport "github.com/stephrobert/scankit/report"

	"pavois/internal/audit"
	"pavois/internal/engine"
	"pavois/internal/render"
)

var (
	scProfile    string
	scEngine     string
	scOut        string
	scSSHPass    string
	scSSHPrompt  bool
	scKey        string
	scSudo       bool
	scSudoPrompt bool
	scOnTarget   bool
	scStandard   string
	scControls   []string
	scLevel      string
	scFailUnder  int
	scFormat     string
	scFrom       string
)

var scanCmd = &cobra.Command{
	Use:   "scan <local|user@hôte|conteneur>",
	Short: "Audit a target (effective config) and grade A-E",
	Args:  cobra.ExactArgs(1),
	RunE:  runScan,
}

func init() {
	f := scanCmd.Flags()
	f.StringVar(&scProfile, "profile", "", "override the auto-detected per-OS profile (path or URL to a custom profile)")
	f.StringVar(&scEngine, "engine", "auto", "auto | native | docker")
	f.StringVar(&scOut, "out", "", "JSON output dir (default: <root>/reports)")
	f.StringVar(&scSSHPass, "ssh-pass", "", "SSH password (discouraged — leaks via ps/history; prefer --ssh-prompt or a key)")
	f.BoolVar(&scSSHPrompt, "ssh-prompt", false, "prompt for the SSH password (no echo; also reads PAVOIS_SSH_PASSWORD)")
	f.StringVar(&scKey, "key", "", "SSH private key")
	f.BoolVar(&scSudo, "sudo", false, "run as root via sudo (effective config of a service)")
	f.BoolVar(&scSudoPrompt, "sudo-prompt", false, "prompt for the sudo password (no echo; also reads PAVOIS_SUDO_PASSWORD); implies --sudo")
	f.BoolVar(&scOnTarget, "on-target", false, "run the scan ON the target (local://) — far fewer SSH round-trips, much faster")
	f.StringVar(&scStandard, "standard", "", "audit a single standard: bp28|cis|pci-dss|nist|stig (see: Pavois standards)")
	f.StringVar(&scLevel, "level", "", "level (e.g. --standard cis --level 1)")
	f.IntVar(&scFailUnder, "fail-under", -1, "exit code 1 if grade < PCT/100")
	f.StringVarP(&scFormat, "format", "f", "table", "format: table | json | sarif | junit | csv | html")
	f.StringVar(&scFrom, "from", "", "evaluate an existing InSpec JSON report (no scan)")
	f.StringArrayVar(&scControls, "controls", nil, "run ONLY these control ids (fast single-rule iteration, e.g. --controls ssh-disable-root-login)")
	rootCmd.AddCommand(scanCmd)
}

func machineTransport(target string) (machine, transport string) {
	switch {
	case target == "local":
		h, _ := os.Hostname()
		return h, "local://"
	case strings.Contains(target, "@"):
		return strings.SplitN(strings.SplitN(target, "@", 2)[1], ":", 2)[0], "ssh://"
	case engine.IsSSHAlias(target): // alias ~/.ssh/config
		return target, "ssh://"
	default:
		return target, "docker://"
	}
}

// profileForOS maps a detected OS (name + release) to a bundled linux profile
// directory name under profiles/linux/, or "" if unknown.
func profileForOS(name, release string) string {
	major := strings.SplitN(release, ".", 2)[0]
	switch name {
	case "debian":
		return "debian" + major
	case "ubuntu":
		return "ubuntu" + strings.ReplaceAll(release, ".", "")
	case "fedora":
		return "fedora"
	case "almalinux":
		if major == "9" {
			return "almalinux9"
		}
		return "rhel" + major
	case "rhel", "redhat", "centos", "rocky", "ol", "oracle":
		return "rhel" + major
	}
	return ""
}

// familyOf : préfixe de profil de la même FAMILLE (pour le repli au plus proche).
func familyOf(name string) string {
	switch name {
	case "ubuntu":
		return "ubuntu"
	case "debian":
		return "debian"
	case "fedora":
		return "fedora"
	case "almalinux", "rhel", "redhat", "centos", "rocky", "ol", "oracle":
		return "rhel" // les clones RHEL retombent sur rhel<major> (cf. almalinux9 à part)
	}
	return ""
}

// latestFamilyProfile : profil de la famille au plus haut numéro de version
// présent sous profiles/linux/ (ex. ubuntu2204/ubuntu2404 -> ubuntu2404).
func latestFamilyProfile(root, fam string) string {
	entries, _ := os.ReadDir(filepath.Join(root, "profiles", "linux"))
	best, bestN := "", -1
	for _, e := range entries {
		if !e.IsDir() || !strings.HasPrefix(e.Name(), fam) {
			continue
		}
		n := 0
		_, _ = fmt.Sscanf(strings.TrimPrefix(e.Name(), fam), "%d", &n) // parse failure leaves n=0 (intended fallback)
		if n > bestN {
			best, bestN = e.Name(), n
		}
	}
	return best
}

// detectProfile interroge la CIBLE (cinc detect, tout transport) et renvoie le
// profil linux. Repli au plus proche de la même famille si la version exacte
// n'est pas embarquée (ex. Ubuntu 26.04 -> ubuntu2404), SANS dupliquer de corpus.
func detectProfile(root string, o engine.Options) (profile, detected string) {
	name, release := engine.Detect(o)
	if name == "" {
		return "", ""
	}
	detected = name + " " + release
	dir := func(p string) bool {
		fi, err := os.Stat(filepath.Join(root, "profiles", "linux", p))
		return err == nil && fi.IsDir()
	}
	if cand := profileForOS(name, release); cand != "" && dir(cand) {
		return "linux/" + cand, detected
	}
	if fam := familyOf(name); fam != "" {
		if near := latestFamilyProfile(root, fam); near != "" {
			_, _ = fmt.Fprintf(os.Stderr, "pavois: no exact profile for %s — using closest %s\n", detected, near)
			return "linux/" + near, detected
		}
	}
	return "", detected
}

func runScan(cmd *cobra.Command, args []string) error {
	root := findRoot()
	target := args[0]
	machine, transport := machineTransport(target)

	// Resolve secrets ONCE, up front, and drop them from our own environment so no
	// child process (the detect probe, cinc exec) can inherit them. Passwords reach
	// cinc only over stdin (--config -), never argv. See engine.secretsConfig.
	sudo := scSudo || scSudoPrompt
	sudoPass, err := resolveSudoPass(scSudoPrompt)
	if err != nil {
		return fmt.Errorf("read sudo password: %w", err)
	}
	sshPass, err := resolveSSHPass(scSSHPass, scSSHPrompt)
	if err != nil {
		return fmt.Errorf("read SSH password: %w", err)
	}

	// Détection de l'OS de la CIBLE (cinc detect, tout transport) pour choisir le
	// bon profil sans demander à l'utilisateur — et signaler un profil qui ne
	// correspond pas à la machine testée.
	_, _ = fmt.Fprint(os.Stderr, "  ⠿ detecting target OS…\r")
	detOpts := engine.Options{Target: target, Key: scKey, SSHPass: sshPass}
	autoProf, detectedOS := detectProfile(root, detOpts)
	_, _ = fmt.Fprint(os.Stderr, "\033[K")
	if !cmd.Flags().Changed("profile") {
		// No --profile given: the per-OS profile is auto-selected from the detected OS.
		// If detection finds nothing usable, fail clearly rather than fall back to a
		// phantom default (there is no generic bundled profile).
		if autoProf == "" {
			hint := "could not detect the target OS"
			if detectedOS != "" {
				hint = "no bundled profile for " + detectedOS
			}
			return fmt.Errorf("%s — pass --profile <path|url> (e.g. profiles/linux/debian12)", hint)
		}
		scProfile = autoProf
		_, _ = fmt.Fprintf(os.Stderr, "pavois: detected %s → profile %s\n", detectedOS, autoProf)
	} else if autoProf != "" && !strings.HasSuffix(scProfile, autoProf) {
		// même profil sous une autre forme de chemin (profiles/linux/x, ./x) = OK ;
		// on n'avertit que si le profil désigne vraiment un autre OS.
		_, _ = fmt.Fprintf(os.Stderr, "pavois: ⚠ profile %s may not match target OS %s (suggested: %s)\n",
			scProfile, detectedOS, autoProf)
	}

	jsonPath := scFrom
	if jsonPath == "" {
		out := scOut
		if out == "" {
			out = filepath.Join(root, "reports")
		}
		_ = os.MkdirAll(out, 0o750)
		ts := time.Now().Format("20060102-150405")
		jsonPath = filepath.Join(out, fmt.Sprintf("rapport-%s-%s-%s.json",
			slug(machine), strings.TrimSuffix(transport, "://"), ts))
		rc, err := engine.Run(engine.Options{
			Root: root, Target: target, Profile: scProfile, Engine: scEngine,
			SSHPass: sshPass, SudoPass: sudoPass, Key: scKey, Sudo: sudo, JSONOut: jsonPath,
			Standard: scStandard, Level: scLevel, // n'exécute que la norme demandée
			OnTarget: scOnTarget, Controls: scControls,
		})
		if err != nil {
			return err
		}
		_ = rc // 100/101 = des contrôles échouent : exploité via la note/--fail-under
	}

	rep, err := audit.Load(jsonPath)
	if err != nil {
		return err
	}

	// Rapport HTML autoporté multi-normes (note A->E côté client), à côté du JSON.
	htmlPath := strings.TrimSuffix(jsonPath, ".json") + ".html"
	htmlStr, nctrl, nnorm := render.HTML(rep, render.Meta{
		Machine: machine, Transport: transport,
		Timestamp: time.Now().Format("2006-01-02 15:04:05 MST"),
		Engine:    "CINC Auditor (InSpec)",
	})
	if err := os.WriteFile(htmlPath, []byte(htmlStr), 0o600); err == nil {
		_, _ = fmt.Fprintf(os.Stderr, "pavois: report %s (%d controls, %d standards)\n", htmlPath, nctrl, nnorm)
	}

	res := audit.Evaluate(rep, machine, scStandard, scLevel)
	scope := scStandard
	if scope == "" {
		scope = "all standards"
	}
	if scLevel != "" {
		scope += " · level " + scLevel
	}
	// Pas de SummaryHeadline : la note est rendue en grosse lettre en bas (pas de
	// doublon avec les compteurs du résumé).
	opts := reportOptions(version, scope, fmt.Sprintf("%s (%s) · %s", machine, strings.TrimSuffix(transport, "://"), res.OS), "")

	// Sortie : défaut = présentation scankit (comme pitstop/plumber) ; sinon un
	// format machine optionnel, propre sur stdout, pour une chaîne CI/CD.
	out := cmd.OutOrStdout()
	switch scFormat {
	case "json":
		letter, pts, rq := audit.GradeResult(res)
		_ = json.NewEncoder(out).Encode(map[string]any{
			"grade": letter, "points": pts, "passed": res.Passed, "total": res.Total,
			"runtime_qualified": rq, "qualified_passes": res.Qualified,
			"counts": res.Summary.Counts, "findings": res.Findings,
			"posture": audit.Breakdown(rep, scStandard, scLevel),
		})
	case "sarif":
		if err := screport.SARIF(out, opts, machine, res.Findings); err != nil {
			return err
		}
	case "junit":
		if err := screport.JUnit(out, opts, res.Findings, res.Total); err != nil {
			return err
		}
	case "csv":
		if err := screport.CSV(out, res.Findings); err != nil {
			return err
		}
	case "html":
		_, _ = fmt.Fprint(out, htmlStr)
	default:
		// Ordre aligné sur pitstop/plumber : bandeau → écarts → résumé, et la NOTE
		// en GROSSE LETTRE tout EN BAS. Au terminal on ne montre que critical/high ;
		// le détail complet (medium/low) est dans le rapport HTML.
		if res.Total == 0 {
			_, _ = fmt.Fprintf(out, "  No controls evaluated — is standard %q present in profile %q?\n\n",
				scStandard, scProfile)
			break
		}
		top := onlySeverities(res.Findings, "critical", "high", "medium")
		screport.Terminal(out, opts, top, res.Summary)
		_, _ = fmt.Fprintf(os.Stderr,
			"  %d critical/high/medium deviation(s) shown · %d total · full report → %s\n",
			len(top), len(res.Findings), htmlPath)
		// On ne note (A→E) que les profils à NORMES (profiles/linux/*) ; un profil
		// sans mapping (ex. container-baseline) n'a pas de note.
		if nnorm > 0 {
			letter, pts, _ := audit.GradeResult(res)
			writeScorecard(out, letter, pts, res.Passed, res.Total, res.Qualified)
			writePosture(out, audit.Breakdown(rep, scStandard, scLevel))
		} else {
			_, _ = fmt.Fprintln(out, "  No standard mappings in this profile — grade applies to profiles/linux/* only.")
		}
	}

	if scFailUnder >= 0 && nnorm > 0 {
		if _, pts := audit.Grade(res.Summary); pts < scFailUnder {
			return &ComplianceError{Points: pts, Threshold: scFailUnder}
		}
	}
	return nil
}

func slug(s string) string {
	var b strings.Builder
	prevDash := false
	for _, r := range strings.ToLower(s) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
			prevDash = false
		} else if !prevDash {
			b.WriteByte('-')
			prevDash = true
		}
	}
	return strings.Trim(b.String(), "-")
}
