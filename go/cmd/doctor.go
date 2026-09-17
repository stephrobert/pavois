package cmd

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"

	"pavois/internal/corpus"
	"pavois/internal/engine"
)

// doctor checks that the host is ready to scan and tells the user exactly what to fix. It is
// the zero-friction first step: instead of a first scan failing on a missing CINC engine,
// an ungenerated corpus or no sudo, `pavois doctor` reports each prerequisite and the next
// command to run.
var doctorCmd = &cobra.Command{
	Use:   "doctor",
	Short: "Check the environment is ready to scan (CINC engine, sudo, SSH, OS, rule corpus)",
	Args:  cobra.NoArgs,
	RunE:  runDoctor,
}

// a control declaration starts a line: `control 'id' do`
var controlDecl = regexp.MustCompile(`(?m)^control '`)

// Where to send someone who has no engine. The engine is the one prerequisite a package manager
// cannot fetch (CINC is in no distribution repository), so this string is the answer to the most
// common failure a fresh install meets, and it is worth being one place rather than three.
const engineDocs = "https://pavois.dev/en/installation/#engine"

func init() { rootCmd.AddCommand(doctorCmd) }

func runDoctor(cmd *cobra.Command, _ []string) error {
	out := cmd.OutOrStdout()
	ready := true
	line := func(mark, label, detail string) {
		_, _ = fmt.Fprintf(out, "  [%-4s] %-22s %s\n", mark, label, detail)
	}
	look := func(bin string) (string, bool) { p, err := exec.LookPath(bin); return p, err == nil }

	_, _ = fmt.Fprintln(out, "pavois doctor: environment readiness")
	_, _ = fmt.Fprintln(out)

	// CINC engine (native preferred, docker is the fallback). One of them is required.
	cinc := ""
	if p, ok := look("cinc-auditor"); ok {
		cinc = p
	} else if p, ok := look("inspec"); ok {
		cinc = p
	}
	docker, hasDocker := look("docker")
	switch {
	case cinc != "":
		line("OK", "CINC engine (native)", cinc)
	case hasDocker:
		line("WARN", "CINC engine", "native cinc-auditor missing; the docker fallback will be used ("+docker+"). A container cannot audit its host, so a local:// scan still needs the native engine: "+engineDocs)
	default:
		// Not the omnitruck one-liner upstream documents: that is a script piped into a root shell,
		// and a hardening tool does not ask for that. The page linked here fetches the package URL
		// and its published sha256 from the same endpoint, checks the sum, then installs with the
		// system package manager. Same engine, nothing executed before it has been verified.
		line("FAIL", "CINC engine", "no scan engine: install cinc-auditor ("+engineDocs+") or docker")
		ready = false
	}

	// Privilege + transports.
	if p, ok := look("sudo"); ok {
		line("OK", "sudo", p)
	} else {
		line("WARN", "sudo", "not found; effective-config reads (sshd -T, sysctl...) need root, pass --sudo")
	}
	if p, ok := look("ssh"); ok {
		line("OK", "ssh", p)
	} else {
		line("WARN", "ssh", "not found; remote scans (user@host) need ssh")
	}

	// Rule corpus: the .rb the scanner executes are generated from the reference.
	//
	// This used to count the .rb FILES and call them controls: it reported "301 controls" on a
	// corpus of 620 for debian12 alone, because a domain file holds many controls. A doctor that
	// misreports the size of the corpus is worse than one that says nothing.
	root := findRoot()
	rb, _ := filepath.Glob(filepath.Join(root, "profiles", "linux", "*", "controls", "*.rb"))
	ctrls, oses := 0, map[string]bool{}
	_ = bytes.MinRead
	for _, f := range rb {
		b, err := os.ReadFile(f) //nolint:gosec // path from our own glob under the repo root
		if err != nil {
			continue
		}
		ctrls += len(controlDecl.FindAll(b, -1))
		oses[filepath.Base(filepath.Dir(filepath.Dir(f)))] = true
	}
	switch {
	case len(rb) > 0:
		line("OK", "rule corpus", fmt.Sprintf("%d controls rendered across %d OS profile(s)", ctrls, len(oses)))
	case corpus.Available():
		line("OK", "rule corpus", "embedded in this binary (self-contained release build)")
	default:
		line("WARN", "rule corpus", "not generated; run `mise run regen` (renders the .rb corpus + OSCAL from the reference)")
	}

	// What this binary CARRIES, beyond the rule corpus.
	//
	// A released binary reads six things that no package manager can install and no user can be
	// asked to supply: the per-OS reference, the norm catalogue, the baseline identity, the audit
	// ruleset, the kernel-build recipes and the behavioral probes. They are compiled in with
	// //go:embed, and an EMPTY embed directory is not a build error: it links, it ships, and the
	// only symptom is a sentence the first time a user runs the command that needs it. v0.1.2
	// shipped exactly that, with three of the six empty, and nothing anywhere said so.
	//
	// So doctor says so. A user who meets "this binary embeds none and none is on disk" can now run
	// one command and see which asset is missing, instead of filing an issue about `harden plan`.
	var missingAssets []string
	for _, a := range []struct {
		label string
		count func() (string, error)
	}{
		{"hardening reference", func() (string, error) {
			n := referenceOSes(root)
			if len(n) == 0 {
				return "", fmt.Errorf("none")
			}
			return fmt.Sprintf("%d system(s): %s", len(n), strings.Join(n, ", ")), nil
		}},
		{"norm catalogue", func() (string, error) {
			b, err := readNormCatalogue(root)
			if err != nil {
				return "", err
			}
			var doc struct {
				Standards map[string]any `yaml:"standards"`
			}
			if yaml.Unmarshal(b, &doc) != nil || len(doc.Standards) == 0 {
				return "", fmt.Errorf("unreadable")
			}
			return fmt.Sprintf("%d standard(s)", len(doc.Standards)), nil
		}},
		{"baseline identity", func() (string, error) {
			m := readBaseline(root)
			// The defaults are the tell: readBaseline keeps them when the file is unreachable, so
			// a catalogue dated 1970 is what a downloaded binary published for two releases.
			if m.Version == "0.0.0" || m.Released == "1970-01-01" {
				return "", fmt.Errorf("not embedded (oscal would publish version 0.0.0, released 1970-01-01)")
			}
			return fmt.Sprintf("%s %s, released %s", m.Name, m.Version, m.Released), nil
		}},
		{"audit ruleset", func() (string, error) {
			b, err := readAuditRules(root)
			if err != nil {
				return "", err
			}
			n := 0
			for _, l := range strings.Split(string(b), "\n") {
				if strings.HasPrefix(l, "-a ") || strings.HasPrefix(l, "-w ") {
					n++
				}
			}
			if n == 0 {
				return "", fmt.Errorf("present but holds no rule")
			}
			return fmt.Sprintf("%d rule(s)", n), nil
		}},
		{"behavioral probes", func() (string, error) {
			b, err := readBehavioralProbes(root)
			if err != nil {
				return "", err
			}
			var doc struct {
				Probes []struct{} `yaml:"probes"`
			}
			if yaml.Unmarshal(b, &doc) != nil || len(doc.Probes) == 0 {
				return "", fmt.Errorf("present but holds no probe")
			}
			return fmt.Sprintf("%d probe(s)", len(doc.Probes)), nil
		}},
		{"kernel-build recipes", func() (string, error) {
			// Counted against the systems the reference covers, not against zero. A binary carrying
			// eight of nine recipes cannot do kernel-build for the ninth, and reports nothing about
			// it: the gap only appears on the machine that runs that OS.
			var missing []string
			oses := referenceOSes(root)
			for _, osn := range oses {
				if b, err := readKernelRecipe(root, osn); err != nil || len(b) == 0 {
					missing = append(missing, osn)
				}
			}
			if len(missing) > 0 {
				return "", fmt.Errorf("missing for %d of %d system(s): %s",
					len(missing), len(oses), strings.Join(missing, ", "))
			}
			return fmt.Sprintf("%d system(s)", len(oses)), nil
		}},
	} {
		if detail, err := a.count(); err != nil {
			line("FAIL", a.label, err.Error()+"; this binary was built without it, "+
				"so the commands that read it cannot work. Report it with `pavois version`.")
			missingAssets = append(missingAssets, a.label)
			ready = false
		} else {
			line("OK", a.label, detail)
		}
	}

	// Local OS detection (only meaningful if a native engine is present).
	if cinc != "" {
		if name, rel := engine.Detect(engine.Options{Target: "local"}); name != "" {
			line("OK", "local OS detected", fmt.Sprintf("%s %s", name, rel))
		} else {
			line("WARN", "local OS", "could not detect the local OS via cinc-auditor")
		}
	}

	_, _ = fmt.Fprintln(out)
	// The advice has to match what is actually missing. A binary built without an embedded asset
	// used to be told to install a scan engine, with the engine sitting right there in the OK line
	// above: nothing the reader could do would fix it, and the one thing that would (get a working
	// build) was not mentioned.
	if len(missingAssets) > 0 {
		return fmt.Errorf("not ready: this binary was built without %s. No installation fixes that: "+
			"download the release binary again, or build from a checkout with `mise run embed:all`",
			strings.Join(missingAssets, ", "))
	}
	if !ready {
		return fmt.Errorf("not ready: install a scan engine (cinc-auditor or docker), then re-run pavois doctor")
	}
	_, _ = fmt.Fprintln(out, "ready: try: pavois scan local --sudo")
	return nil
}
