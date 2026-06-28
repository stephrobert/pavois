package cmd

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
)

var servePort int

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Serve HTML reports over HTTP",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, _ []string) error {
		dir := filepath.Join(findRoot(), "reports")
		if fi, err := os.Stat(dir); err != nil || !fi.IsDir() {
			return fmt.Errorf("no report yet. Run first: pavois scan ...")
		}
		addr := fmt.Sprintf(":%d", servePort)
		fmt.Fprintf(cmd.OutOrStdout(),
			"pavois: reports at http://localhost%s/  (Ctrl+C to stop)\n", addr)
		return http.ListenAndServe(addr, http.FileServer(http.Dir(dir)))
	},
}

func init() {
	serveCmd.Flags().IntVar(&servePort, "port", 8098, "HTTP listen port")
	rootCmd.AddCommand(serveCmd)
}
