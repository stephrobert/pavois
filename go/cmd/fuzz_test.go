package cmd

import (
	"strings"
	"testing"
)

// plannedTargets decides what a rollback RESTORES and, for files pavois created, what it DELETES.
// It derives that from the compiled recipe by regex. A parsing slip there does not produce a wrong
// report, it deletes the wrong file on someone's host, which makes it the highest-stakes parser in
// the codebase and the one worth fuzzing. The invariants below are the ones the rollback's safety
// rests on: it must never panic on any recipe text, and it must never hand the restore script a
// path it cannot restore precisely (a glob, or an empty string that would resolve to /).
func FuzzPlannedTargets(f *testing.F) {
	f.Add("")
	f.Add("file '/etc/ssh/sshd_config.d/00-pavois.conf' do\n  content 'x'\nend\n")
	f.Add("package 'auditd' do\n  action :install\nend\n")
	f.Add("service 'auditd' do\n  action :enable\nend\n")
	f.Add("execute 'x' do\n  command 'apt-get install -y acct'\nend\n")
	f.Add("execute 'y' do\n  command 'sed -i s/a/b/ /etc/login.defs'\nend\n")
	f.Add("file '/var/log/*.log' do\nend\n") // a glob must never be captured
	f.Add("file '' do\nend\n")               // an empty path must never be captured
	f.Add("template '/etc/audit/rules.d/x.rules' do\nend\n")
	f.Add("directory '/etc/pavois.d' do\nend\n")

	f.Fuzz(func(t *testing.T, recipe string) {
		// An empty plan is the honest baseline: everything captured must come from the recipe text.
		files, pkgs, svcs, irr := plannedTargets(planFile{OS: "debian12"}, recipe)

		for _, fl := range files {
			if fl.Path == "" {
				t.Fatalf("captured an EMPTY path: a rollback would resolve it to / (recipe %q)", recipe)
			}
			if strings.ContainsAny(fl.Path, "*?") {
				t.Fatalf("captured a glob %q: a rollback cannot restore what it cannot enumerate", fl.Path)
			}
			// Every captured path must actually occur in the recipe: the capture is only
			// trustworthy if it is READ from the text, never synthesised.
			if !strings.Contains(recipe, fl.Path) {
				t.Fatalf("captured path %q does not appear in the recipe", fl.Path)
			}
		}
		for _, p := range pkgs {
			if p.Name == "" {
				t.Fatalf("captured an empty package name (recipe %q)", recipe)
			}
		}
		for _, s := range svcs {
			if s.Name == "" {
				t.Fatalf("captured an empty service name (recipe %q)", recipe)
			}
		}
		for _, i := range irr {
			if i == "" {
				t.Fatalf("emitted an empty irreversible entry: the operator would see a blank warning")
			}
		}
	})
}
