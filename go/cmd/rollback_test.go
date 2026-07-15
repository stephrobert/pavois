package cmd

import (
	"os"
	"path/filepath"
	"testing"
)

// TestPlannedTargetsFromRecipe freezes the load-bearing property of the rollback: what it captures
// is read OFF THE COMPILED RECIPE, not a hardcoded table (the table drifted within the hour once).
// A file/package/service that appears in the recipe must be captured; a glob must not.
func TestPlannedTargetsFromRecipe(t *testing.T) {
	recipe := `
file '/etc/ssh/sshd_config.d/00-pavois.conf' do
  content 'PermitRootLogin no'
end
template '/etc/audit/rules.d/pavois.rules' do
end
directory '/etc/pavois.d' do
end
package 'auditd' do
  action :install
end
apt_package 'apparmor' do
end
service 'auditd' do
  action :enable
end
execute 'install acct' do
  command 'apt-get install -y acct'
end
execute 'tidy' do
  command 'sed -i s/x/y/ /etc/login.defs'
end
file '/var/log/*.log' do
end
`
	tru := true
	p := planFile{OS: "debian12"}
	p.Rules = map[string]struct {
		Apply           *bool          `yaml:"apply"`
		Acknowledged    *bool          `yaml:"acknowledged"`
		Danger          string         `yaml:"danger"`
		Status          string         `yaml:"status"`
		Choose          string         `yaml:"choose"`
		SSHAllowFrom    []string       `yaml:"ssh_allow_from"`
		SSHAllowUsers   []string       `yaml:"ssh_allow_users"`
		SSHAllowGroups  []string       `yaml:"ssh_allow_groups"`
		Remediation     map[string]any `yaml:"remediation"`
		RequiresPackage string         `yaml:"requires_package"`
	}{
		"mount-tmp": {Apply: &tru, Remediation: map[string]any{"resource": "mount", "name": "/tmp"}},
	}

	files, pkgs, svcs, irr := plannedTargets(p, recipe)

	wantFiles := map[string]bool{
		"/etc/ssh/sshd_config.d/00-pavois.conf": true,
		"/etc/audit/rules.d/pavois.rules":       true,
		"/etc/pavois.d":                         true,
		"/etc/login.defs":                       true, // the path the exec'd sed edits
	}
	got := map[string]bool{}
	for _, f := range files {
		got[f.Path] = true
		if f.Path == "/var/log/*.log" {
			t.Errorf("a glob was captured as a restorable file: %q", f.Path)
		}
	}
	for f := range wantFiles {
		if !got[f] {
			t.Errorf("recipe file not captured: %q", f)
		}
	}

	pkgSet := map[string]bool{}
	for _, p := range pkgs {
		pkgSet[p.Name] = true
	}
	for _, want := range []string{"auditd", "apparmor", "acct"} { // acct comes from the exec-install
		if !pkgSet[want] {
			t.Errorf("package not captured: %q", want)
		}
	}

	svcSet := map[string]bool{}
	for _, s := range svcs {
		svcSet[s.Name] = true
	}
	if !svcSet["auditd"] {
		t.Errorf("service auditd not captured")
	}

	// a mount remediation is irreversible and must be NAMED, not silently dropped
	if len(irr) == 0 {
		t.Errorf("mount remediation should be flagged irreversible")
	}
}

// TestSha256File is the integrity gate the root-level `tar -P -C /` extraction depends on: the
// same bytes hash the same, a changed byte hashes differently.
func TestSha256File(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "rp.tar.gz")
	if err := os.WriteFile(p, []byte("restore-point-payload"), 0o600); err != nil {
		t.Fatal(err)
	}
	h1, _, err := sha256File(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(h1) != 64 {
		t.Errorf("sha256 hex length = %d, want 64", len(h1))
	}
	h2, _, _ := sha256File(p)
	if h1 != h2 {
		t.Errorf("hash not stable: %s vs %s", h1, h2)
	}
	if err := os.WriteFile(p, []byte("restore-point-payloaD"), 0o600); err != nil {
		t.Fatal(err)
	}
	h3, _, _ := sha256File(p)
	if h3 == h1 {
		t.Errorf("hash did not change after the file changed")
	}
}
