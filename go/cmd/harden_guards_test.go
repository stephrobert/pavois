package cmd

import (
	"strings"
	"testing"
)

// The recipe is Ruby that another program runs, minutes later, as root, on someone else's machine.
// Nothing in the Go build sees it, `ruby -c` would accept it, and compileRecipe's other tests only
// look for the resources they expect. So a typo inside a guard block survives every gate here and
// surfaces as a converge that dies halfway through.
//
// That is not hypothetical: `only_if { :File.directory?(path) }` shipped for months. `:File` is a
// Ruby SYMBOL, not the File class, and a real campaign on debian13 ended with
//
//	NoMethodError: directory[/etc/cron.hourly] had an error:
//	undefined method 'directory?' for an instance of Symbol
//
// after the run had already changed part of the system. This test asserts the shape of what is
// emitted, which is the only check that stands between a Ruby typo and a half-applied host.
func TestGeneratedGuardsReferenceRubyConstants(t *testing.T) {
	plan := loadPlan(t, `
target: pavois@host
os: debian12
rules:
  file-cron-hourly-perms:
    apply: true
    status: gap
    remediation:
      resource: file
      path: /etc/cron.hourly
      mode: "0700"
      owner: root
      group: root
`)

	recipe, _, _, _, _ := compileRecipe(plan, "", "", "", "")

	// `:File` is a Symbol; `::File` is the class. The first is what broke a live converge.
	if strings.Contains(recipe, "{ :File.") || strings.Contains(recipe, "(:File.") {
		t.Errorf("the recipe calls a method on the SYMBOL :File, which raises NoMethodError at "+
			"converge time. Use ::File.\n%s", recipe)
	}

	// Every Ruby constant used inside a guard must be top-level qualified, because the block is
	// evaluated in the resource's context, not in the recipe's.
	for _, bare := range []string{"{ File.", "{ Dir.", "{ IO."} {
		if strings.Contains(recipe, bare) {
			t.Errorf("guard uses %q unqualified; use the :: form so it resolves from the resource "+
				"context", strings.TrimPrefix(bare, "{ "))
		}
	}
}
