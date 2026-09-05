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
	scAllowContainer    bool
	scAllowUnprivileged bool
	scProfile           string
	scEngine            string
	scOut               string
	scSSHPass           string
	scSSHPrompt         bool
	scKey               string
	scSudo              bool
	scSudoPrompt        bool
	scOnTarget          bool
	scStandard          string
	scControls          []string
	scLevel             string
	scFailUnder         int
	scFormat            string
	scFrom              string
)

var scanCmd = &cobra.Command{
	Use:   "scan <local|user@host|container>",
	Short: "Audit a target (effective config) and grade A-E",
	Args:  cobra.ExactArgs(1),
	RunE:  runScan,
}

func init() {
	f := scanCmd.Flags()
	f.StringVar(&scProfile, "profile", "", "override the auto-detected per-OS profile (path or URL to a custom profile)")
	f.StringVar(&scEngine, "engine", "auto", "auto | native | docker")
	f.StringVar(&scOut, "out", "", "JSON output dir (default: <root>/reports)")
	f.StringVar(&scSSHPass, "ssh-pass", "", "SSH password (discouraged: leaks via ps/history; prefer --ssh-prompt or a key)")
	f.BoolVar(&scSSHPrompt, "ssh-prompt", false, "prompt for the SSH password (no echo; also reads PAVOIS_SSH_PASSWORD)")
	f.StringVar(&scKey, "key", "", "SSH private key")
	f.BoolVar(&scSudo, "sudo", false, "run as root via sudo (effective config of a service)")
	f.BoolVar(&scSudoPrompt, "sudo-prompt", false, "prompt for the sudo password (no echo; also reads PAVOIS_SUDO_PASSWORD); implies --sudo")
	f.BoolVar(&scOnTarget, "on-target", false, "run the scan ON the target (local://): far fewer SSH round-trips, much faster")
	f.StringVar(&scStandard, "standard", "", "audit a single standard: bp28|cis|pci-dss|nist|stig (see: Pavois standards)")
	f.StringVar(&scLevel, "level", "", "level (e.g. --standard cis --level 1)")
	f.IntVar(&scFailUnder, "fail-under", -1, "exit code 1 if grade < PCT/100")
	f.StringVarP(&scFormat, "format", "f", "table", "format: table | json | sarif | junit | csv | html")
	f.StringVar(&scFrom, "from", "", "evaluate an existing InSpec JSON report (no scan)")
	f.StringArrayVar(&scControls, "controls", nil, "run ONLY these control ids (fast single-rule iteration, e.g. --controls ssh-disable-root-login)")
	f.BoolVar(&scAllowContainer, "allow-container", false, "scan a container with a full per-OS profile anyway (kernel controls then measure the HOST, not the target)")
	f.BoolVar(&scAllowUnprivileged, "allow-unprivileged", false, "scan without root anyway (checks that need privilege will report deviations they never measured)")
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
	case "almalinux", "rhel", "redhat", "centos", "rocky", "ol", "oracle":
		return "rhel" + major
	}
	return ""
}

// familyOf: profile prefix of the same FAMILY (for the closest fallback).
func familyOf(name string) string {
	switch name {
	case "ubuntu":
		return "ubuntu"
	case "debian":
		return "debian"
	case "fedora":
		return "fedora"
	case "almalinux", "rhel", "redhat", "centos", "rocky", "ol", "oracle":
		return "rhel" // RHEL family + clones (AlmaLinux, Rocky, Oracle...) map to rhel<major>
	}
	return ""
}

// latestFamilyProfile: the family profile with the highest version number
// present under profiles/linux/ (e.g. ubuntu2204/ubuntu2404 -> ubuntu2404).
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

// detectProfile queries the TARGET (cinc detect, any transport) and returns the
// linux profile. Falls back to the closest of the same family when the exact
// version is not bundled (e.g. Ubuntu 26.04 -> ubuntu2404), WITHOUT duplicating the corpus.
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
			_, _ = fmt.Fprintf(os.Stderr, "pavois: no exact profile for %s: using closest %s\n", detected, near)
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

	// Detect the TARGET OS (cinc detect, any transport) to pick the right profile
	// without asking the user: and flag a profile that does not match the machine
	// under test.
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
			return fmt.Errorf("%s: pass --profile <path|url> (e.g. profiles/linux/debian12)", hint)
		}
		scProfile = autoProf
		_, _ = fmt.Fprintf(os.Stderr, "pavois: detected %s → profile %s\n", detectedOS, autoProf)
	} else if autoProf != "" && !strings.HasSuffix(scProfile, autoProf) {
		// same profile under a different path form (profiles/linux/x, ./x) = OK;
		// only warn if the profile really designates a different OS.
		_, _ = fmt.Fprintf(os.Stderr, "pavois: ⚠ profile %s may not match target OS %s (suggested: %s)\n",
			scProfile, detectedOS, autoProf)
	}

	// A check that cannot run the command it asserts on does not produce a verdict, it produces
	// noise with a severity attached. Refuse rather than hand back findings nobody measured.
	if !scAllowUnprivileged && !sudo && scFrom == "" {
		if uid, known := engine.EffectiveUID(detOpts); known && uid != 0 {
			return fmt.Errorf("scanning as a non-root user (uid %d) without --sudo.\n"+
				"  %s asserts on the output of privileged commands (sshd -T, auditctl -l, sysctl -a, "+
				"systemctl show). Unprivileged they return nothing, and every check on them reports a "+
				"deviation that was never measured: a compliant host reads back as grade E with "+
				"fabricated CRITICAL findings.\n"+
				"  add --sudo (or --sudo-prompt), or\n"+
				"  override deliberately: --allow-unprivileged", uid, scProfile)
		}
	}

	// A container cannot answer for a kernel it does not own, so refuse before spending a scan on
	// a report that would be green and meaningless.
	if !scAllowContainer {
		if isCT, kind := engine.IsContainer(detOpts); isCT {
			return fmt.Errorf("target is a %s container, and %s reads kernel state owned by the HOST "+
				"(sysctl, kconfig, modules, mounts, audit, cmdline). A container shares the host kernel, "+
				"so those controls would describe the host and the report would be green and meaningless.\n"+
				"  scan a VM or a real host instead, or\n"+
				"  override deliberately: --allow-container (kernel controls then report on the host)", kind, scProfile)
		}
	}

	jsonPath := scFrom
	reportsDir := scOut
	if reportsDir == "" {
		reportsDir = filepath.Join(root, "reports")
	}
	ts := time.Now().Format("20060102-150405")
	if jsonPath == "" {
		_ = os.MkdirAll(reportsDir, 0o750)
		// Interim name; renamed to <date>_<os>_<target>_<grade> once the scan is graded.
		jsonPath = filepath.Join(reportsDir, ".pavois-scanning-"+ts+".json")
		rc, err := engine.Run(engine.Options{
			Root: root, Target: target, Profile: scProfile, Engine: scEngine,
			SSHPass: sshPass, SudoPass: sudoPass, Key: scKey, Sudo: sudo, JSONOut: jsonPath,
			Standard: scStandard, Level: scLevel, // only runs the requested standard
			OnTarget: scOnTarget, Controls: scControls,
		})
		if err != nil {
			return err
		}
		_ = rc // 100/101 = controls fail: used via the grade/--fail-under
	}

	rep, err := audit.Load(jsonPath)
	if err != nil {
		return err
	}

	res := audit.Evaluate(rep, machine, scStandard, scLevel)

	// Name the report so a directory listing is self-describing and chronologically sortable:
	//   <YYYYMMDD-HHMM>_<os>_<target>_<grade>.{json,html}   e.g. 20260701-1405_debian12_web01_B
	// Only when we produced the scan (not with --from, which points at the user's own file).
	if scFrom == "" {
		letter, _, _ := audit.GradeResult(res)
		stamp := ts
		if len(stamp) >= 13 {
			stamp = stamp[:13] // YYYYMMDD-HHMM (drop the seconds)
		}
		osSlug := slug(strings.ReplaceAll(strings.TrimSpace(res.OS), " ", ""))
		if osSlug == "" {
			osSlug = "os"
		}
		final := filepath.Join(reportsDir, fmt.Sprintf("%s_%s_%s_%s.json", stamp, osSlug, slug(machine), letter))
		if err := os.Rename(jsonPath, final); err == nil {
			jsonPath = final
		}
	}

	// Self-contained multi-standard HTML report (client-side A->E grade), next to the JSON.
	htmlPath := strings.TrimSuffix(jsonPath, ".json") + ".html"
	htmlStr, nctrl, nnorm := render.HTML(rep, render.Meta{
		Machine: machine, Transport: transport,
		Timestamp: time.Now().Format("2006-01-02 15:04:05 MST"),
		Engine:    "CINC Auditor (InSpec)",
	})
	if err := os.WriteFile(htmlPath, []byte(htmlStr), 0o600); err == nil {
		_, _ = fmt.Fprintf(os.Stderr, "pavois: report %s (%d controls, %d standards)\n", htmlPath, nctrl, nnorm)
	}
	scope := scStandard
	if scope == "" {
		scope = "all standards"
	}
	if scLevel != "" {
		scope += " · level " + scLevel
	}
	// No SummaryHeadline: the grade is rendered as a large letter at the bottom (no
	// duplication with the summary counters).
	opts := reportOptions(version, scope, fmt.Sprintf("%s (%s) · %s", machine, strings.TrimSuffix(transport, "://"), res.OS), "")

	// Output: default = scankit presentation (like pitstop/plumber); otherwise an
	// optional machine format, clean on stdout, for a CI/CD pipeline.
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
		// Order aligned with pitstop/plumber: banner → gaps → summary, and the GRADE
		// as a LARGE LETTER right at the BOTTOM. In the terminal we only show critical/high;
		// the full detail (medium/low) is in the HTML report.
		if res.Total == 0 {
			_, _ = fmt.Fprintf(out, "  No controls evaluated: is standard %q present in profile %q?\n\n",
				scStandard, scProfile)
			break
		}
		top := onlySeverities(res.Findings, "critical", "high", "medium")
		_ = screport.Terminal(out, opts, top, res.Summary) // best-effort render to the terminal sink
		_, _ = fmt.Fprintf(os.Stderr,
			"  %d critical/high/medium deviation(s) shown · %d total · full report → %s\n",
			len(top), len(res.Findings), htmlPath)
		// We only grade (A→E) profiles with STANDARDS (profiles/linux/*); a profile
		// without mappings (e.g. container-baseline) has no grade.
		if nnorm > 0 {
			letter, pts, _ := audit.GradeResult(res)
			writeScorecard(out, letter, pts, res.Passed, res.Total, res.Qualified, res.Waived, res.NotApplicable)
			writePosture(out, audit.Breakdown(rep, scStandard, scLevel))
		} else {
			_, _ = fmt.Fprintln(out, "  No standard mappings in this profile: grade applies to profiles/linux/* only.")
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
