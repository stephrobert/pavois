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
	"pavois/internal/corpus"
	"pavois/internal/engine"
	"pavois/internal/render"
)

var (
	scAllowContainer    bool
	scBootstrapCinc     bool
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
	f.StringVarP(&scFormat, "format", "f", "table", "format: table | json | sarif | junit | csv | html | oscal")
	f.StringVar(&scFrom, "from", "", "evaluate an existing InSpec JSON report (no scan)")
	f.StringArrayVar(&scControls, "controls", nil, "run ONLY these control ids (fast single-rule iteration, e.g. --controls ssh-disable-root-login)")
	f.BoolVar(&scAllowContainer, "allow-container", false, "scan a container with a full per-OS profile anyway (kernel controls then measure the HOST, not the target)")
	f.BoolVar(&scAllowUnprivileged, "allow-unprivileged", false, "scan without root anyway (checks that need privilege will report deviations they never measured)")
	f.BoolVar(&scBootstrapCinc, "bootstrap-cinc", false, "let Pavois install cinc-auditor ON the target when it is missing (an unpinned installer, run as root there)")
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
	// Same two sources as dir() above, and for the same reason: on a downloaded binary the disk
	// listing is empty, and falling back to the family is exactly the case where an exact match was
	// already missing. Reading only the disk turned "no exact profile, using the closest" into
	// "no bundled profile at all".
	names := corpus.Names()
	if entries, err := os.ReadDir(filepath.Join(root, "profiles", "linux")); err == nil {
		for _, e := range entries {
			if e.IsDir() {
				names = append(names, e.Name())
			}
		}
	}

	best, bestN := "", -1
	for _, name := range names {
		if !strings.HasPrefix(name, fam) {
			continue
		}
		n := 0
		_, _ = fmt.Sscanf(strings.TrimPrefix(name, fam), "%d", &n) // parse failure leaves n=0 (intended fallback)
		if n > bestN {
			best, bestN = name, n
		}
	}
	return best
}

// detectProfileWhy also returns why detection failed, so the caller can tell "no profile for this
// OS" (pass --profile) from "the target did not answer" (a key, a password, a route).
func detectProfileWhy(root string, o engine.Options) (profile, detected, why string) {
	name, release, why := engine.DetectWhy(o)
	if name == "" {
		return "", "", why
	}
	return profileForPlatform(root, name, release)
}

// profileForPlatform maps an ALREADY KNOWN platform to a bundled profile, without touching any
// machine. Split out of detectProfileWhy so `--from` can use it: an archived report carries its own
// platform, so re-grading it needs no probe, no engine and no target. That was not true before, and
// `scan local --from report.json` refused to run on any host without cinc-auditor installed, which
// is most of them, while the flag's own help says "no scan" and the handbook promises it regrades an
// archived result without touching the host.
func profileForPlatform(root, name, release string) (profile, detected, why string) {
	detected = strings.TrimSpace(name + " " + release)
	// Disk OR embedded. A checkout has profiles/ on disk; a downloaded binary has the corpus
	// compiled in and nothing on disk. Asking only the filesystem is what made every artifact of
	// v0.1.0 answer "no bundled profile for debian 12.15" on a machine where the rules were in fact
	// sitting inside the binary that printed the error.
	dir := func(p string) bool {
		if fi, err := os.Stat(filepath.Join(root, "profiles", "linux", p)); err == nil && fi.IsDir() {
			return true
		}
		return corpus.Has(filepath.Join("linux", p))
	}
	if cand := profileForOS(name, release); cand != "" && dir(cand) {
		return "linux/" + cand, detected, ""
	}
	if fam := familyOf(name); fam != "" {
		if near := latestFamilyProfile(root, fam); near != "" {
			_, _ = fmt.Fprintf(os.Stderr, "pavois: no exact profile for %s: using closest %s\n", detected, near)
			return "linux/" + near, detected, ""
		}
	}
	return "", detected, "no bundled profile for " + detected
}

// reportsDirDefault is where a scan writes when --out is not given. One place, because the sudo
// re-exec has to hand the same directory back to the user afterwards (#281).
func reportsDirDefault() string {
	return filepath.Join(findRoot(), "reports")
}

func runScan(cmd *cobra.Command, args []string) error {
	root := findRoot()
	target := args[0]
	machine, transport := machineTransport(target)

	// `--sudo` on a local target: re-run the whole command as root, because a local transport
	// cannot elevate itself and every entry point recommends this exact form (#281). Before the
	// banner, before any file is written: the child does the work, the parent only waits.
	if handled, err := reexecUnderSudo(target == "local", scSudo || scSudoPrompt); handled || err != nil {
		return err
	}

	// `--bootstrap-cinc` only ever applied to a remote target: on a local one the scan died on the
	// missing engine before the flag was ever consulted, so a user on a machine without CINC read
	// the flag, passed it, and got an error that did not mention it (#283). Say so instead, and say
	// it before the OS detection that used to fail first. Silence on a flag the user passed is the
	// worst of the three outcomes.
	if target == "local" && scBootstrapCinc {
		return fmt.Errorf("--bootstrap-cinc applies to a REMOTE target only.\n" +
			"  it installs the engine on the machine being audited, over ssh. This machine IS the\n" +
			"  machine being audited, and Pavois does not install software on the host running it.\n" +
			"  install cinc-auditor here, verified rather than piped: " + engineDocs)
	}

	// Resolve secrets ONCE, up front, and drop them from our own environment so no
	// child process (the detect probe, cinc exec) can inherit them. Passwords reach
	// cinc only over stdin (--config -), never argv. See engine.secretsConfig.
	sudo := scSudo || scSudoPrompt
	// cinc rejects --sudo on a local transport, and it is right to: a process cannot grant itself
	// privileges. By the time we get here a local --sudo has already re-executed as root, so the
	// intent is satisfied and the flag must not be forwarded (#281).
	engineSudo := sudo && target != "local"
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
	//
	// With --from there is nothing to detect: the report names its own platform, and the target
	// argument is a label for the output, not a machine to reach. Probing it anyway made
	// `scan <anything> --from report.json` fail on a host with no CINC engine, which is every host
	// that is not already a scanning station. Re-grading an archived report is precisely the case
	// where the machine may be long gone.
	detOpts := engine.Options{Target: target, Key: scKey, SSHPass: sshPass}
	var autoProf, detectedOS, detectWhy string
	if scFrom != "" {
		rep, err := audit.Load(scFrom)
		if err != nil {
			return fmt.Errorf("read %s: %w", scFrom, err)
		}
		autoProf, detectedOS, detectWhy = profileForPlatform(root, rep.Platform.Name, rep.Platform.Release)
	} else {
		_, _ = fmt.Fprint(os.Stderr, "  ⠿ detecting target OS…\r")
		autoProf, detectedOS, detectWhy = detectProfileWhy(root, detOpts)
		_, _ = fmt.Fprint(os.Stderr, "\033[K")
	}
	if !cmd.Flags().Changed("profile") {
		// No --profile given: the per-OS profile is auto-selected from the detected OS.
		// If detection finds nothing usable, fail clearly rather than fall back to a
		// phantom default (there is no generic bundled profile).
		if autoProf == "" {
			// Two very different failures reach here and want opposite answers: an OS with no
			// bundled profile wants --profile; a target that never answered wants a key, a
			// password or a route. Sending the second one to --profile fixes nothing.
			if detectedOS == "" {
				return fmt.Errorf("could not reach or identify %s: %s%s\n"+
					"  If the host is fine and simply has no bundled profile, pass --profile",
					target, detectWhy, withTarget(sshFailureHint(scKey), target))
			}
			return fmt.Errorf("no bundled profile for %s: pass --profile <path|url> (e.g. profiles/linux/debian12)", detectedOS)
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
	// a report that would be green and meaningless. With --from there is no scan to spend and no
	// target to ask: the probe would reach a machine that has nothing to do with the archived run.
	if !scAllowContainer && scFrom == "" {
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
		reportsDir = reportsDirDefault()
	}
	ts := time.Now().Format("20060102-150405")
	if jsonPath == "" {
		_ = os.MkdirAll(reportsDir, 0o750)
		// Interim name; renamed to <date>_<os>_<target>_<grade> once the scan is graded.
		jsonPath = filepath.Join(reportsDir, ".pavois-scanning-"+ts+".json")
		rc, err := engine.Run(engine.Options{
			Root: root, Target: target, Profile: scProfile, Engine: scEngine,
			SSHPass: sshPass, SudoPass: sudoPass, Key: scKey, Sudo: engineSudo, JSONOut: jsonPath,
			Standard: scStandard, Level: scLevel, // only runs the requested standard
			OnTarget: scOnTarget, Controls: scControls, Bootstrap: scBootstrapCinc,
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

	// A scan that evaluated NOTHING is not a pass, it is an absence of measurement. The grade is
	// 100 minus the weight of the failures, so an empty run loses nothing and scores a clean "A":
	// a profile that failed to load, a bad --profile path, a corpus that was never rendered, all
	// report the target as perfect. This was reproduced by pointing a scan at a freshly cloned
	// checkout, where profiles/linux/<os>/controls is generated and therefore empty: grade A, on a
	// stock cloud image, having read nothing at all.
	if res.Total == 0 && res.NotApplicable == 0 && res.Waived == 0 {
		return fmt.Errorf("the scan evaluated 0 controls, so there is nothing to grade "+
			"(an empty result would otherwise score a perfect A having measured nothing).\n"+
			"  profile: %s\n"+
			"  if it is a bundled profile, the corpus may not be rendered yet: run `mise run regen`\n"+
			"  if it is a path or URL, check that it contains controls/*.rb", scProfile)
	}

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
	// Both files exist now, so hand them back. `--sudo` on a local target re-runs this process as
	// root, and a root process writing into the caller's directory leaves them unable to delete
	// their own report. Only root can give a file away, so this is done here and not in the parent.
	RestoreOwnership(reportsDir)
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

	// Run-level provenance (tool + ruleset digests, target, timestamp, scope): the envelope
	// that makes the machine-exchange outputs (JSON, OSCAL) reproducible and opposable.
	run := scanProvenance(root, scProfile, transport, machine, rep, scStandard, scLevel, scFrom != "", time.Now())

	// Output: default = scankit presentation (like pitstop/plumber); otherwise an
	// optional machine format, clean on stdout, for a CI/CD pipeline.
	out := cmd.OutOrStdout()
	switch scFormat {
	case "json":
		letter, pts, rq := audit.GradeResult(res)
		_ = json.NewEncoder(out).Encode(map[string]any{
			"grade": letter, "points": pts, "passed": res.Passed, "total": res.Total,
			"runtime_qualified": rq, "qualified_passes": res.Qualified,
			// `total` is the DENOMINATOR, not the profile size, and these three say where the
			// difference went. Without them a pipeline reads 287/541 and cannot tell whether the
			// other 112 controls do not address this host, were accepted as risks, or simply were
			// not measured. The terminal has printed waived and n/a for a while; the machine
			// format, which is the one a gate actually parses, printed neither.
			"waived": res.Waived, "not_applicable": res.NotApplicable,
			"unmeasured": res.Unmeasured,
			"counts":     res.Summary.Counts, "findings": res.Findings,
			"posture": audit.Breakdown(rep, scStandard, scLevel),
			"run":     run, // provenance: host/OS, tool + ruleset digests, timestamp, scope
		})
	case "oscal":
		// OSCAL 1.1.2 assessment-results, the standard machine form of the run outcome
		// (reviewed-controls + observations + findings), provenance stamped in metadata.
		if err := screport.OSCAL(out, audit.Assessment(rep, run, machine, scStandard, scLevel)); err != nil {
			return err
		}
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
			writeScorecard(out, letter, pts, res.Passed, res.Total, res.Qualified, res.Waived, res.NotApplicable, res.Unmeasured)
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
