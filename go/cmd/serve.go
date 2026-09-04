package cmd

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"

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
			return fmt.Errorf("no report yet: run a scan first (pavois scan)")
		}
		addr := fmt.Sprintf(":%d", servePort)
		_, _ = fmt.Fprintf(cmd.OutOrStdout(),
			"pavois: reports at http://localhost%s/  (Ctrl+C to stop)\n", addr)
		srv := &http.Server{
			Addr:              addr,
			Handler:           http.FileServer(http.Dir(dir)),
			ReadHeaderTimeout: 10 * time.Second, // mitigate slowloris (gosec G114)
			ReadTimeout:       30 * time.Second,
			WriteTimeout:      60 * time.Second,
			IdleTimeout:       120 * time.Second,
		}
		return srv.ListenAndServe()
	},
}

func init() {
	serveCmd.Flags().IntVar(&servePort, "port", 8098, "HTTP listen port")
	rootCmd.AddCommand(serveCmd)
}
