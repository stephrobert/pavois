package cmd

import (
	"fmt"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"

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

func init() { rootCmd.AddCommand(doctorCmd) }

func runDoctor(cmd *cobra.Command, _ []string) error {
	out := cmd.OutOrStdout()
	ready := true
	line := func(mark, label, detail string) {
		_, _ = fmt.Fprintf(out, "  [%-4s] %-22s %s\n", mark, label, detail)
	}
	look := func(bin string) (string, bool) { p, err := exec.LookPath(bin); return p, err == nil }

	_, _ = fmt.Fprintln(out, "pavois doctor — environment readiness")
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
		line("WARN", "CINC engine", "native cinc-auditor missing; the docker fallback will be used ("+docker+"). For a local:// scan, install cinc-auditor: https://omnitruck.cinc.sh")
	default:
		line("FAIL", "CINC engine", "install cinc-auditor (curl https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc-auditor) or docker")
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
	root := findRoot()
	rb, _ := filepath.Glob(filepath.Join(root, "profiles", "linux", "*", "controls", "*.rb"))
	if len(rb) > 0 {
		line("OK", "rule corpus", fmt.Sprintf("%d controls rendered under profiles/linux/", len(rb)))
	} else {
		line("WARN", "rule corpus", "not generated; run `mise run regen` (renders the .rb corpus + OSCAL from the reference)")
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
	if !ready {
		return fmt.Errorf("not ready: install a scan engine (cinc-auditor or docker), then re-run pavois doctor")
	}
	_, _ = fmt.Fprintln(out, "ready — try:  pavois scan local --sudo")
	return nil
}
