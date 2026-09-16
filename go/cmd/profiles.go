package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"pavois/internal/corpus"
	"sort"
	"strings"

	"github.com/spf13/cobra"

	"pavois/internal/engine"
)

var profilesCmd = &cobra.Command{
	Use:   "profiles",
	Short: "List bundled profiles",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, _ []string) error {
		root := findRoot()
		out := cmd.OutOrStdout()
		_, _ = fmt.Fprintln(out, "Bundled profiles:")

		// Disk first, then whatever is embedded and was not already listed. A checkout has
		// profiles/ on disk; a downloaded binary has only the compiled-in corpus, and this
		// command used to walk the disk alone. It printed an empty list on every installed
		// copy of v0.1.0, which reads as "this tool has no rules" rather than as a bug.
		seen := map[string]bool{}
		_ = filepath.WalkDir(filepath.Join(root, "profiles"), func(p string, d os.DirEntry, err error) error {
			if err != nil || !d.IsDir() {
				return nil
			}
			yml := filepath.Join(p, "inspec.yml")
			if _, e := os.Stat(yml); e != nil || strings.HasPrefix(d.Name(), "_") {
				return nil
			}
			rel, _ := filepath.Rel(filepath.Join(root, "profiles"), p)
			seen[rel] = true
			_, _ = fmt.Fprintf(out, "  %-26s %s\n", rel, titleOf(yml))
			return nil
		})
		for _, name := range corpus.Names() {
			rel := filepath.Join("linux", name)
			if seen[rel] {
				continue
			}
			_, _ = fmt.Fprintf(out, "  %-26s %s\n", rel, corpus.Title(rel))
		}
		bin := engine.NativeBin()
		if bin == "" {
			bin = "absent (docker mode)"
		}
		_, _ = fmt.Fprintf(out, "\nNative engine: %s\n", bin)
		return nil
	},
}

func titleOf(yml string) string {
	b, err := os.ReadFile(yml)
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "title:") {
			return strings.Trim(strings.TrimSpace(strings.TrimPrefix(line, "title:")), `"`)
		}
	}
	return ""
}

var _ = sort.Strings

func init() { rootCmd.AddCommand(profilesCmd) }
