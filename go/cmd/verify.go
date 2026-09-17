package cmd

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

// verify is BEHAVIORAL validation: it attempts the forbidden action and confirms the
// protection actually holds: tool-independent proof a remediation is operational,
// beyond reading config. Probes live in docs/reference/behavioral-probes.yml (extensible).
var verifyCmd = &cobra.Command{
	Use:   "verify <target>",
	Short: "Behavioral validation: attempt the forbidden action, confirm the protection holds",
	Args:  cobra.ExactArgs(1),
	RunE:  runVerify,
}

var vfKey string

func init() {
	verifyCmd.Flags().StringVar(&vfKey, "key", "", "SSH private key for the target")
	rootCmd.AddCommand(verifyCmd)
}

type probe struct {
	ID     string `yaml:"id"`
	Title  string `yaml:"title"`
	Run    string `yaml:"run"`
	Cmd    string `yaml:"cmd"`
	Expect string `yaml:"expect"`
}

func runVerify(cmd *cobra.Command, args []string) error {
	target := args[0] // full user@host: used as-is for the on-target SSH
	host := target
	if i := strings.LastIndex(target, "@"); i >= 0 {
		host = target[i+1:]
	}

	raw, err := readBehavioralProbes(findRoot())
	if err != nil {
		return err
	}
	var doc struct {
		Probes []probe `yaml:"probes"`
	}
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		return err
	}

	out := cmd.OutOrStdout()
	_, _ = fmt.Fprintf(out, "pavois: behavioral validation of %s: does the hardening actually block the threat?\n\n", target)
	pass, fail := 0, 0
	for _, p := range doc.Probes {
		c := strings.ReplaceAll(strings.ReplaceAll(p.Cmd, "{host}", host), "{target}", target)
		var run *exec.Cmd
		if p.Run == "from-host" {
			run = exec.Command("sh", "-c", c)
		} else {
			run = exec.Command("ssh", append(sshOptsFor(vfKey), target, c)...)
		}
		stdout, runErr := run.Output()
		ok := false
		switch p.Expect {
		case "fail":
			ok = runErr != nil // the forbidden action failed = protection holds
		case "success":
			ok = runErr == nil
		case "empty":
			ok = runErr == nil && strings.TrimSpace(string(stdout)) == ""
		}
		if ok {
			pass++
			_, _ = fmt.Fprintf(out, "  \033[32m✔\033[0m %s\n", p.Title)
		} else {
			fail++
			detail := strings.TrimSpace(string(stdout))
			if detail != "" && len(detail) < 80 {
				detail = " (" + detail + ")"
			} else {
				detail = ""
			}
			_, _ = fmt.Fprintf(out, "  \033[31m✗\033[0m %s%s\n", p.Title, detail)
		}
	}
	_, _ = fmt.Fprintf(out, "\npavois: %d/%d behavioral probes confirm the protection holds.\n", pass, pass+fail)
	if fail > 0 {
		return fmt.Errorf("%d behavioral probe(s) failed: the hardening is NOT operational", fail)
	}
	return nil
}
