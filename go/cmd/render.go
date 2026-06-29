package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"pavois/internal/audit"
	"pavois/internal/render"
)

var (
	renderOut       string
	renderMachine   string
	renderTransport string
	renderEngine    string
	renderTimestamp string
)

// render turns a stored scan report (.json) back into the self-contained HTML report,
// offline and with no target. It lets a committed, anonymized report fixture be
// re-rendered into the site's sample report (see `mise gen:example`): the example stays
// current and is leak-free by construction, since the fixture carries no real data.
var renderCmd = &cobra.Command{
	Use:   "render <report.json>",
	Short: "Render a stored scan report (.json) to the self-contained HTML report, offline",
	Args:  cobra.ExactArgs(1),
	RunE:  runRender,
}

func init() {
	renderCmd.Flags().StringVarP(&renderOut, "out", "o", "", "write HTML here (default: stdout)")
	renderCmd.Flags().StringVar(&renderMachine, "machine", "", "machine label for the report header")
	renderCmd.Flags().StringVar(&renderTransport, "transport", "ssh", "transport label for the report header")
	renderCmd.Flags().StringVar(&renderEngine, "engine", "CINC Auditor (InSpec)", "engine label for the report header")
	renderCmd.Flags().StringVar(&renderTimestamp, "timestamp", "", "timestamp label for the report header")
	rootCmd.AddCommand(renderCmd)
}

func runRender(cmd *cobra.Command, args []string) error {
	rep, err := audit.Load(args[0])
	if err != nil {
		return err
	}
	htmlStr, nctrl, nnorm := render.HTML(rep, render.Meta{
		Machine: renderMachine, Transport: renderTransport,
		Timestamp: renderTimestamp, Engine: renderEngine,
	})
	if renderOut == "" {
		_, _ = fmt.Fprint(cmd.OutOrStdout(), htmlStr)
		return nil
	}
	if err := os.WriteFile(renderOut, []byte(htmlStr), 0o644); err != nil {
		return fmt.Errorf("write %s: %w", renderOut, err)
	}
	_, _ = fmt.Fprintf(os.Stderr, "pavois: report %s (%d controls, %d standards)\n", renderOut, nctrl, nnorm)
	return nil
}
