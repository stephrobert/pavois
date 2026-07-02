package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// version is injected at build time via -ldflags "-X pavois/cmd.version=...".
var version = "dev"

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print pavois version",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, _ []string) error {
		_, _ = fmt.Fprintln(cmd.OutOrStdout(), "Pavois", version)
		return nil
	},
}

func init() { rootCmd.AddCommand(versionCmd) }
