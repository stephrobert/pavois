package cmd

import (
	"encoding/json"
	"os"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
)

// The CLI reference on the site was hand-written prose, and it drifted from the binary exactly like
// the rule fiches did: two commands (`render`, `standards`) had never been documented at all, and
// the flags of one command were attributed to another. A CLI can describe itself, so it does: this
// walks the real cobra tree and emits it, and the site is generated from that. Nothing to keep in
// sync, because there is only one source.
//
//	pavois clidocs            # the whole command tree as JSON

type cliFlag struct {
	Name      string `json:"name"`
	Shorthand string `json:"shorthand,omitempty"`
	Usage     string `json:"usage"`
	Default   string `json:"default,omitempty"`
	Type      string `json:"type"`
}

// The exit codes are a CONTRACT with every pipeline that calls pavois, and the site stated three
// different versions of them: 0/1/2 on one page, "0 pass, 100 failures, 101 error" on another. The
// truth is here, in the code that produces them (root.go Execute): CINC's own 100/101 are swallowed
// internally (a failing control is a normal outcome, not an error), so they never reach the shell.
type cliExit struct {
	Code    int    `json:"code"`
	Meaning string `json:"meaning"`
}

var exitCodes = []cliExit{
	{0, "compliant: the run succeeded and, if --fail-under was set, the grade met the threshold"},
	{1, "non-compliance: the grade is below --fail-under (the gate a CI job acts on)"},
	{2, "technical error: pavois or the engine could not complete the run"},
}

type cliCmd struct {
	Name     string    `json:"name"`
	Path     string    `json:"path"`  // "pavois harden apply"
	Short    string    `json:"short"` // one-liner, as printed in --help
	Long     string    `json:"long,omitempty"`
	Use      string    `json:"use"` // argument shape, e.g. "scan <target>"
	Examples []string  `json:"examples,omitempty"`
	Flags    []cliFlag `json:"flags,omitempty"`
	Sub      []cliCmd  `json:"sub,omitempty"`
}

func flagsOf(fs *pflag.FlagSet) []cliFlag {
	var out []cliFlag
	fs.VisitAll(func(f *pflag.Flag) {
		if f.Hidden || f.Name == "help" {
			return
		}
		out = append(out, cliFlag{
			Name: f.Name, Shorthand: f.Shorthand, Usage: f.Usage,
			Default: f.DefValue, Type: f.Value.Type(),
		})
	})
	return out
}

// A cobra Example block is free text; the site wants the command lines, so keep the lines that are
// commands and drop the prose around them.
func examplesOf(c *cobra.Command) []string {
	var out []string
	for _, l := range strings.Split(c.Example, "\n") {
		l = strings.TrimSpace(l)
		if strings.HasPrefix(l, "pavois ") || strings.HasPrefix(l, "$ pavois ") {
			out = append(out, strings.TrimPrefix(l, "$ "))
		}
	}
	return out
}

func describe(c *cobra.Command, parent string) cliCmd {
	path := strings.TrimSpace(parent + " " + c.Name())
	d := cliCmd{
		Name: c.Name(), Path: path, Short: c.Short, Long: c.Long,
		Use: c.Use, Examples: examplesOf(c), Flags: flagsOf(c.LocalFlags()),
	}
	for _, s := range c.Commands() {
		// `completion` and `help` are cobra's own plumbing, not part of what pavois does.
		if s.Hidden || s.Name() == "completion" || s.Name() == "help" || s.Name() == "clidocs" {
			continue
		}
		d.Sub = append(d.Sub, describe(s, path))
	}
	return d
}

var clidocsCmd = &cobra.Command{
	Use:    "clidocs",
	Short:  "Emit the CLI reference as JSON (the site's command documentation is generated from it)",
	Hidden: true, // plumbing: it documents pavois, it is not something an operator runs
	RunE: func(_ *cobra.Command, _ []string) error {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		root := describe(rootCmd, "")
		return enc.Encode(struct {
			cliCmd
			ExitCodes []cliExit `json:"exit_codes"`
		}{root, exitCodes})
	},
}

func init() { rootCmd.AddCommand(clidocsCmd) }
