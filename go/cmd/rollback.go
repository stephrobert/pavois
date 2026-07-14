package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

// Undo. No hardening tool has it.
//
// OpenSCAP hands you a bash script and wishes you luck; Lynis only advises; CIS-CAT does not
// remediate at all; an Ansible role is not a transaction either. So "we tested on a clone" is the
// industry's whole answer, and it is why most operators never apply a remediation to production.
//
// pavois can do better for one specific reason: the plan says, BEFORE anything runs, exactly which
// files, packages and services the converge will touch. That is enough to photograph the prior
// state and put it back.
//
// A restore point is:
//   - the CONTENT of every file the recipe is about to write (and the list of the ones that did not
//     exist yet, so a rollback deletes them rather than restoring a ghost);
//   - the installed/absent state of every package it is about to install or remove;
//   - the enabled/active state of every service it is about to enable, disable or mask.
//
// What it does NOT claim: a rollback is not a time machine. A `kernel_build`, a repartition, a
// `dconf` database rebuild or anything that ran through `exec` can have side effects outside the
// files we captured, and the manifest says so per item. Restoring a config file cannot un-reboot a
// machine. We restore what we photographed, we name what we could not, and we never pretend the two
// are the same.

var (
	rbKey        string
	rbSudoPrompt bool
	rbYes        bool
)

type rpFile struct {
	Path    string `json:"path"`
	Existed bool   `json:"existed"` // false -> a rollback DELETES it (pavois created it)
}

type rpPkg struct {
	Name      string `json:"name"`
	Installed bool   `json:"installed_before"`
	Action    string `json:"action"` // install | remove
}

type rpSvc struct {
	Name    string `json:"name"`
	Enabled string `json:"enabled_before"` // enabled | disabled | masked | unknown
	Active  string `json:"active_before"`  // active | inactive | unknown
	Action  string `json:"action"`         // enable | disable | mask
}

type restorePoint struct {
	Target   string   `json:"target"`
	OS       string   `json:"os"`
	Created  string   `json:"created"`
	Plan     string   `json:"plan"`
	Files    []rpFile `json:"files"`
	Packages []rpPkg  `json:"packages"`
	Services []rpSvc  `json:"services"`
	// Remediations whose effects a file-level rollback cannot fully undo. Named, never hidden.
	Irreversible []string `json:"irreversible,omitempty"`
}

// The aggregated drop-ins the recipe writes for a whole FAMILY of controls: they are not named in
// any single remediation, so they have to be listed here or a rollback would leave them behind.
//
//nolint:gosec // G101 false positive: these are FILE PATHS pavois writes, not credentials
var aggregatedDropIns = map[string]string{
	"sshd_setting":   "/etc/ssh/sshd_config.d/99-pavois.conf",
	"sysctl":         "/etc/sysctl.d/zz-pavois.conf",
	"kernel_cmdline": "/etc/default/grub.d/99-pavois-cmdline.cfg",
	"audit_ruleset":  "/etc/audit/rules.d/99-pavois.rules",
	"grub_password":  "/etc/grub.d/40_pavois_password",
	"pam_faillock":   "/etc/security/faillock.conf",
	"selinux_state":  "/etc/selinux/config",
	"mount":          "/etc/fstab",
}

// An `exec` or a kernel build can reach outside the files we photographed. Say which.
var irreversibleResources = map[string]string{
	"kernel_build": "builds and installs a kernel; a rollback restores config files, not the kernel",
	"exec":         "runs a command; its side effects outside the captured files are not undone",
	"dconf":        "rebuilds the dconf database; the compiled db is not captured",
	"mount":        "changes /etc/fstab; a mount already made is not unmounted by a rollback",
}

// plannedTargets walks the ENABLED rules of a plan and returns everything the converge will touch.
// This is the whole trick: the plan is declarative, so the blast radius is knowable in advance.
func plannedTargets(p planFile) ([]rpFile, []rpPkg, []rpSvc, []string) {
	files := map[string]bool{}
	pkgs := map[string]string{}
	svcs := map[string]string{}
	irr := map[string]bool{}

	add := func(path string) {
		if path != "" {
			files[path] = true
		}
	}
	for id, r := range p.Rules {
		if r.Apply == nil || !*r.Apply || r.Remediation == nil {
			continue
		}
		res := s(r.Remediation["resource"])
		if why, ok := irreversibleResources[res]; ok {
			irr[fmt.Sprintf("%s (%s): %s", id, res, why)] = true
		}
		if agg, ok := aggregatedDropIns[res]; ok {
			add(agg)
		}
		switch res {
		case "file", "directory":
			add(s(r.Remediation["path"]))
		case "keyval", "conf_line", "pam_line":
			add(s(r.Remediation["file"]))
			add(s(r.Remediation["path"]))
		case "kernel_module":
			if n := s(r.Remediation["name"]); n != "" {
				add("/etc/modprobe.d/pavois-" + n + ".conf")
			}
		case "package":
			if n := s(r.Remediation["name"]); n != "" {
				pkgs[n] = s(r.Remediation["action"])
			}
		case "service":
			if n := s(r.Remediation["name"]); n != "" {
				pkgs := s(r.Remediation["action"])
				svcs[n] = pkgs
			}
		}
		// a remediation that first installs its prerequisite package also owns that package
		if r.RequiresPackage != "" {
			pkgs[r.RequiresPackage] = "install"
		}
	}
	for _, b := range p.BaselinePackages {
		if b.Apply {
			pkgs[b.Name] = "install"
		}
	}

	var fs []rpFile
	for f := range files {
		fs = append(fs, rpFile{Path: f})
	}
	sort.Slice(fs, func(i, j int) bool { return fs[i].Path < fs[j].Path })

	var ps []rpPkg
	for n, a := range pkgs {
		if a == "" {
			a = "install"
		}
		ps = append(ps, rpPkg{Name: n, Action: a})
	}
	sort.Slice(ps, func(i, j int) bool { return ps[i].Name < ps[j].Name })

	var ss []rpSvc
	for n, a := range svcs {
		ss = append(ss, rpSvc{Name: n, Action: a})
	}
	sort.Slice(ss, func(i, j int) bool { return ss[i].Name < ss[j].Name })

	var is []string
	for k := range irr {
		is = append(is, k)
	}
	sort.Strings(is)
	return fs, ps, ss, is
}

// captureScript photographs the prior state ON the target: a tar of the files that exist, and the
// state of each package and service. Read-only except for the tar it writes to /tmp.
func captureScript(rp restorePoint) string {
	var b strings.Builder
	b.WriteString("set -u\numask 077\nrm -rf /tmp/pavois-rp && mkdir -p /tmp/pavois-rp\n")
	b.WriteString("touch /tmp/pavois-rp/present.txt /tmp/pavois-rp/absent.txt\n")
	for _, f := range rp.Files {
		fmt.Fprintf(&b, "if [ -e %q ]; then echo %q >> /tmp/pavois-rp/present.txt; else echo %q >> /tmp/pavois-rp/absent.txt; fi\n",
			f.Path, f.Path, f.Path)
	}
	// -P: keep the absolute paths, so the restore extracts them straight back where they came from
	b.WriteString("tar czf /tmp/pavois-rp/files.tar.gz -P -T /tmp/pavois-rp/present.txt 2>/dev/null || true\n")
	b.WriteString(": > /tmp/pavois-rp/pkgs.txt\n")
	for _, p := range rp.Packages {
		fmt.Fprintf(&b, "if (command -v dpkg-query >/dev/null && dpkg-query -W -f='${Status}' %q 2>/dev/null | grep -q 'install ok installed') "+
			"|| (command -v rpm >/dev/null && rpm -q %q >/dev/null 2>&1); "+
			"then echo '%s installed' >> /tmp/pavois-rp/pkgs.txt; else echo '%s absent' >> /tmp/pavois-rp/pkgs.txt; fi\n",
			p.Name, p.Name, p.Name, p.Name)
	}
	b.WriteString(": > /tmp/pavois-rp/svcs.txt\n")
	for _, sv := range rp.Services {
		fmt.Fprintf(&b, "echo \"%s $(systemctl is-enabled %q 2>/dev/null || echo unknown) $(systemctl is-active %q 2>/dev/null || echo unknown)\" >> /tmp/pavois-rp/svcs.txt\n",
			sv.Name, sv.Name, sv.Name)
	}
	b.WriteString("tar czf /tmp/pavois-restore-point.tar.gz -C /tmp/pavois-rp . && echo pavois-rp-ok\n")
	return b.String()
}

// restoreScript puts the photograph back: files verbatim, files pavois created deleted, packages and
// services returned to their prior state, and the daemons reloaded so the CHANGE IS EFFECTIVE (a
// restored sshd_config that nobody reloaded has rolled back nothing).
const restoreScript = `set -u
cd /tmp/pavois-rp || exit 1
[ -f files.tar.gz ] && tar xzf files.tar.gz -P -C / 2>/dev/null
# files that did NOT exist before the apply: pavois created them, so a rollback removes them
while IFS= read -r f; do [ -n "$f" ] && rm -f "$f"; done < absent.txt
# packages: undo only what we changed, and only in the direction we changed it
while IFS=' ' read -r name state; do
  [ -z "$name" ] && continue
  want=$(grep -E "^$name " /tmp/pavois-rp/pkgs.want.txt 2>/dev/null | awk '{print $2}')
  if [ "$state" = absent ] && [ "$want" = install ]; then
    (command -v apt-get >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -y remove "$name") ||
    (command -v dnf >/dev/null && dnf -y remove "$name") || true
  elif [ "$state" = installed ] && [ "$want" = remove ]; then
    (command -v apt-get >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -y install "$name") ||
    (command -v dnf >/dev/null && dnf -y install "$name") || true
  fi
done < pkgs.txt
# services: back to the state they were in
while IFS=' ' read -r name enabled active; do
  [ -z "$name" ] && continue
  case "$enabled" in
    enabled) systemctl enable "$name" >/dev/null 2>&1 || true ;;
    disabled) systemctl disable "$name" >/dev/null 2>&1 || true ;;
    masked) systemctl mask "$name" >/dev/null 2>&1 || true ;;
  esac
  case "$active" in
    active) systemctl start "$name" >/dev/null 2>&1 || true ;;
    inactive|failed) systemctl stop "$name" >/dev/null 2>&1 || true ;;
  esac
done < svcs.txt
# make the restored configuration EFFECTIVE, which is the whole point of pavois
systemctl daemon-reload >/dev/null 2>&1 || true
sysctl --system >/dev/null 2>&1 || true
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
systemctl restart systemd-journald >/dev/null 2>&1 || true
command -v augenrules >/dev/null && augenrules --load >/dev/null 2>&1 || true
command -v update-grub >/dev/null && update-grub >/dev/null 2>&1 || true
echo pavois-restore-ok
`

var hardenRollbackCmd = &cobra.Command{
	Use:   "rollback <restore-point-dir>",
	Short: "Undo a hardening run: restore the files, packages and services a plan changed",
	Long: `Restore a target to the state a restore point photographed.

` + "`pavois harden apply`" + ` writes a restore point BEFORE it converges (unless --no-restore-point):
the content of every file it is about to write, the list of the ones that did not exist yet, and the
installed/enabled state of every package and service it touches. This puts them back, and reloads the
daemons so the restored configuration is EFFECTIVE, not merely on disk.

It is not a time machine, and the manifest says so: a kernel build, a repartition or an ` + "`exec`" + ` can
have effects outside the captured files. Those items are listed under "irreversible" in the manifest
and are NOT undone.`,
	Args: cobra.ExactArgs(1),
	RunE: runHardenRollback,
}

func init() {
	hardenCmd.AddCommand(hardenRollbackCmd)
	hardenRollbackCmd.Flags().StringVar(&rbKey, "key", "", "SSH private key for the target")
	hardenRollbackCmd.Flags().BoolVar(&rbSudoPrompt, "sudo-prompt", false, "prompt for the sudo password (no echo; also reads PAVOIS_SUDO_PASSWORD)")
	hardenRollbackCmd.Flags().BoolVar(&rbYes, "yes", false, "do not ask for confirmation")
}

func runHardenRollback(cmd *cobra.Command, args []string) error {
	dir := args[0]
	raw, err := os.ReadFile(filepath.Join(dir, "manifest.json"))
	if err != nil {
		return fmt.Errorf("read restore point: %w", err)
	}
	var rp restorePoint
	if err := json.Unmarshal(raw, &rp); err != nil {
		return fmt.Errorf("parse manifest: %w", err)
	}
	out := cmd.OutOrStdout()
	target := rp.Target
	if haTarget != "" {
		target = haTarget
	}

	created := 0
	for _, f := range rp.Files {
		if !f.Existed {
			created++
		}
	}
	_, _ = fmt.Fprintf(out, "pavois: restore point of %s taken %s\n", rp.Target, rp.Created)
	_, _ = fmt.Fprintf(out, "  %d file(s) restored to their prior content, %d file(s) pavois created will be DELETED\n",
		len(rp.Files)-created, created)
	_, _ = fmt.Fprintf(out, "  %d package(s) and %d service(s) returned to their prior state\n", len(rp.Packages), len(rp.Services))
	if len(rp.Irreversible) > 0 {
		_, _ = fmt.Fprintf(out, "\n  ⚠ %d remediation(s) a file-level rollback CANNOT undo:\n", len(rp.Irreversible))
		for _, i := range rp.Irreversible {
			_, _ = fmt.Fprintf(out, "      - %s\n", i)
		}
	}
	if !rbYes {
		_, _ = fmt.Fprintf(out, "\nre-run with --yes to apply this rollback to %s\n", target)
		return nil
	}

	sudoPass, err := resolveSudoPass(rbSudoPrompt)
	if err != nil {
		return fmt.Errorf("read sudo password: %w", err)
	}
	opts := sshOptsFor(rbKey)
	tarPath := filepath.Join(dir, "restore-point.tar.gz")
	_, _ = fmt.Fprintln(os.Stderr, "pavois: shipping the restore point back…")
	scp := exec.Command("scp", append(append(opts, tarPath), target+":/tmp/pavois-restore-point.tar.gz")...) //nolint:gosec // fixed args
	scp.Stdout, scp.Stderr = os.Stderr, os.Stderr
	if err := scp.Run(); err != nil {
		return fmt.Errorf("copy restore point: %w", err)
	}

	// the wanted actions travel with the manifest: the restore must know which direction to undo
	var want strings.Builder
	for _, p := range rp.Packages {
		want.WriteString(p.Name + " " + p.Action + "\n")
	}
	remote := "rm -rf /tmp/pavois-rp && mkdir -p /tmp/pavois-rp && " +
		"tar xzf /tmp/pavois-restore-point.tar.gz -C /tmp/pavois-rp && " +
		"printf %q > /tmp/pavois-rp/pkgs.want.txt && " +
		"bash -s"
	remote = fmt.Sprintf(remote, want.String())
	sudo := "sudo -S "
	if sudoPass == "" {
		sudo = "sudo "
	}
	c := exec.Command("ssh", append(append([]string{"-tt"}, opts...), target, //nolint:gosec // fixed args
		"IFS= read -r __P; "+sudo+"bash -c "+shellQuote(remote)+" <<<\"$__P\"")...)
	c.Stdout, c.Stderr = os.Stderr, os.Stderr
	c.Stdin = strings.NewReader(sudoPass + "\n" + restoreScript)
	if err := c.Run(); err != nil {
		return fmt.Errorf("rollback: %w", err)
	}
	_, _ = fmt.Fprintf(out, "\npavois: rolled back. Re-scan to confirm: pavois scan %s --sudo\n", target)
	return nil
}

func shellQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

// writeRestorePoint captures the prior state and stores it locally, BEFORE the converge runs.
func writeRestorePoint(p planFile, target, planPath, dir string, opts []string, sudoPass string) (string, error) {
	files, pkgs, svcs, irr := plannedTargets(p)
	rp := restorePoint{
		Target: target, OS: p.OS, Created: time.Now().UTC().Format(time.RFC3339),
		Plan: filepath.Base(planPath), Files: files, Packages: pkgs, Services: svcs, Irreversible: irr,
	}
	sudo := "sudo -S "
	if sudoPass == "" {
		sudo = "sudo "
	}
	c := exec.Command("ssh", append(append([]string{"-tt"}, opts...), target, //nolint:gosec // fixed args
		"IFS= read -r __P; "+sudo+"bash -s <<<\"$__P\"")...)
	c.Stdin = strings.NewReader(sudoPass + "\n" + captureScript(rp))
	c.Stderr = os.Stderr
	if err := c.Run(); err != nil {
		return "", fmt.Errorf("capture prior state: %w", err)
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	fetch := exec.Command("scp", append(append(opts, target+":/tmp/pavois-restore-point.tar.gz"), //nolint:gosec // fixed args
		filepath.Join(dir, "restore-point.tar.gz"))...)
	fetch.Stderr = os.Stderr
	if err := fetch.Run(); err != nil {
		return "", fmt.Errorf("fetch restore point: %w", err)
	}
	// which files actually existed: a rollback DELETES the ones pavois created
	present := exec.Command("ssh", append(append(opts, target), "cat /tmp/pavois-rp/present.txt 2>/dev/null")...) //nolint:gosec // fixed args
	o, _ := present.Output()
	existing := map[string]bool{}
	for _, l := range strings.Split(string(o), "\n") {
		if l = strings.TrimSpace(l); l != "" {
			existing[l] = true
		}
	}
	for i := range rp.Files {
		rp.Files[i].Existed = existing[rp.Files[i].Path]
	}
	b, err := json.MarshalIndent(rp, "", "  ")
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(dir, "manifest.json"), append(b, '\n'), 0o600); err != nil {
		return "", err
	}
	return dir, nil
}
