package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

// version est injectée au build via -ldflags "-X pavois/cmd.version=...".
var version = "dev"

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print pavois version",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, _ []string) error {
		fmt.Fprintln(cmd.OutOrStdout(), "Pavois", version)
		return nil
	},
}

func init() { rootCmd.AddCommand(versionCmd) }
