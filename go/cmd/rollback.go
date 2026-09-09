package cmd

import (
	"archive/tar"
	"compress/gzip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

// Undo, owned by the tool that did the hardening.
//
// Among the compliance scanners that remediate, none ships the inverse of its own remediation:
// OpenSCAP hands you a bash script and wishes you luck; the CIS Build Kits apply and do not
// unapply; Lynis and CIS-CAT do not remediate at all; an Ansible role is not a transaction either.
// (Bastille Linux tried it in 2003 with RevertBastille and died; CalCom sells it commercially.)
// Where you have NixOS generations, rpm-ostree or ZFS/LVM snapshots, those are strictly better:
// this is for the mutable hosts that have none. It is why most operators never apply to production.
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
	rbTarget     string
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
	// SHA-256 of restore-point.tar.gz, recorded at capture. A rollback ships that tarball back and
	// extracts it AS ROOT with `tar -P -C /`; verifying the hash first refuses a corrupted or
	// swapped archive before it can write arbitrary paths on the target.
	ArchiveSHA256 string `json:"archive_sha256,omitempty"`
	// Remediations whose effects a file-level rollback cannot fully undo. Named, never hidden.
	Irreversible []string `json:"irreversible,omitempty"`
}

// What the run will touch is READ OFF THE COMPILED RECIPE: the very text that is about to run.
//
// The first version of this hardcoded the aggregated drop-in paths in a table, and the table was
// wrong within the hour: the recipe writes /etc/ssh/sshd_config.d/00-pavois.conf, the table said
// 99-. So the rollback deleted a file that never existed and left the real one in place, and every
// SSH control stayed hardened through a "successful" rollback. A second source of truth drifts the
// moment you write it; there is exactly one here, and it is the recipe.
var (
	recipeFileRe    = regexp.MustCompile(`(?m)^(?:file|template|cookbook_file|remote_file|directory)\s+'([^']+)'`)
	recipePackageRe = regexp.MustCompile(`(?m)^(?:apt_)?package\s+'([^']+)'`)
	recipeServiceRe = regexp.MustCompile(`(?m)^service\s+'([^']+)'`)
	// A remediation can also install a package from inside an `exec` (`apt-get install -y acct`), so
	// the package never appears as a Chef `package` resource: and a rollback left acct and sysstat
	// behind while removing the 30 declared ones. Read those too.
	recipeExecInstallRe = regexp.MustCompile(`(?:apt-get|dnf|yum)\s+(?:-y\s+)?install\s+(?:-y\s+)?([a-z0-9][a-z0-9.+-]*)`)
)

// The config files an `exec` command edits. Deliberately narrow: /etc, /boot and /usr/local paths
// with a plausible file extension or a known name, never a glob or a directory: a rollback must
// restore files it is SURE about, and say so about the rest.
var execPathRe = regexp.MustCompile(`(?:/etc|/boot|/usr/local/(?:s?bin|etc))/[A-Za-z0-9._/-]+`)

// The limits, measured on a live debian12 (a full 268-item apply, then a rollback): 597 of the 620
// controls returned to their exact prior state (96%); 604 of 620 (97%) end in the same verdict.
// The 23 that differ are inherent to undoing an installation, not defects, and they are NAMED
// rather than hidden (three even regress from pass to fail: purging a package orphans its files):
//
//   - a filesystem the run MOUNTED (/tmp as tmpfs) stays mounted: /etc/fstab is restored, but a
//     rollback does not unmount a live filesystem under a running system;
//   - a chmod driven by `find /` cannot be enumerated in advance, so those files are not captured;
//   - PURGING a package we installed removes its system user, and files it left behind become
//     unowned; and removing a tool (apparmor-utils) removes the very command a control checks with.
//
// An honest rollback names what it cannot undo. It never claims to be a time machine.
var irreversibleResources = map[string]string{
	"kernel_build": "builds and installs a kernel; a rollback restores config files, not the kernel",
	"exec":         "runs a command; its side effects outside the captured files are not undone",
	"dconf":        "rebuilds the dconf database; the compiled db is not captured",
	"mount":        "changes /etc/fstab; a mount already made is not unmounted by a rollback",
}

// plannedTargets returns everything the converge will touch: the files, packages and services named
// by the COMPILED RECIPE, plus the remediations whose effects a file-level rollback cannot undo.
// This is the whole trick: the run is declarative, so its blast radius is knowable before it runs.
func plannedTargets(p planFile, recipe string) ([]rpFile, []rpPkg, []rpSvc, []string) {
	files := map[string]bool{}
	pkgs := map[string]string{}
	svcs := map[string]string{}
	irr := map[string]bool{}

	add := func(path string) {
		if path != "" && !strings.ContainsAny(path, "*?") { // a glob is not a file we can restore
			files[path] = true
		}
	}
	// the recipe is the truth about what runs
	for _, m := range recipeFileRe.FindAllStringSubmatch(recipe, -1) {
		add(m[1])
	}
	for _, m := range recipePackageRe.FindAllStringSubmatch(recipe, -1) {
		pkgs[m[1]] = "install"
	}
	for _, m := range recipeExecInstallRe.FindAllStringSubmatch(recipe, -1) {
		pkgs[m[1]] = "install"
	}
	for _, m := range recipeServiceRe.FindAllStringSubmatch(recipe, -1) {
		svcs[m[1]] = "enable"
	}
	// and every /etc path an `exec` command names (a sed, an echo >>, a chmod)
	for _, m := range execPathRe.FindAllString(recipe, -1) {
		add(strings.Trim(m, `"'`+"`"))
	}

	for id, r := range p.Rules {
		if r.Apply == nil || !*r.Apply || r.Remediation == nil {
			continue
		}
		res := s(r.Remediation["resource"])
		if why, ok := irreversibleResources[res]; ok {
			irr[fmt.Sprintf("%s (%s): %s", id, res, why)] = true
		}
		switch res {
		case "package":
			if n := s(r.Remediation["name"]); n != "" {
				pkgs[n] = s(r.Remediation["action"])
			}
		case "service":
			if n := s(r.Remediation["name"]); n != "" {
				svcs[n] = s(r.Remediation["action"])
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
	// tar is not a given. AlmaLinux cloud images ship without it, and the whole restore point
	// is two tar invocations, so the capture produced nothing and said nothing: the failure
	// only surfaced one step later as "fetch restore point: no such file". Check it first and
	// name both ways out, because losing the rollback is a decision, not an accident.
	b.WriteString("set -u\numask 077\n" +
		"if ! command -v tar >/dev/null 2>&1; then\n" +
		"  echo \"pavois: tar is missing on this target, so no restore point can be taken.\" >&2\n" +
		"  echo \"       Install it (dnf install -y tar / apt-get install -y tar), or re-run\" >&2\n" +
		"  echo \"       with --no-restore-point and accept that harden rollback is lost.\" >&2\n" +
		"  exit 1\n" +
		"fi\n" +
		"rm -rf /tmp/pavois-rp && mkdir -p /tmp/pavois-rp\n")
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
	// The tar holds the CONTENT of config files, so it stays 0600: but it is written by root and
	// fetched by the connecting (unprivileged) account, so hand it to that account rather than
	// opening it to the whole box.
	// Fail loudly, here, if the archive cannot be produced. The script runs under `set -u`
	// and used to end on an `echo`, so its exit status described the echo and nothing else:
	// a failed tar returned 0, pavois believed the state was photographed, and the error
	// surfaced one step later as "fetch restore point: no such file", which blames the
	// transfer for what the capture did. Measured on AlmaLinux 8, 9 and 10.
	b.WriteString("if ! tar czf /tmp/pavois-restore-point.tar.gz -C /tmp/pavois-rp .; then\n" +
		"  echo \"pavois: FAILED to archive the restore point (tar exit $?)\" >&2\n" +
		"  exit 1\n" +
		"fi\n" +
		"chown \"${SUDO_USER:-root}\" /tmp/pavois-restore-point.tar.gz || true\n" +
		"chmod 0600 /tmp/pavois-restore-point.tar.gz\n" +
		"if [ ! -s /tmp/pavois-restore-point.tar.gz ]; then\n" +
		"  echo \"pavois: the restore point archive is empty\" >&2\n" +
		"  exit 1\n" +
		"fi\n" +
		"echo pavois-rp-ok\n")
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
    # PURGE, not remove: apt-get remove keeps the conffiles, so removing the 'at' package left
    # /etc/at.deny behind, and a control demanding its absence went from PASS to FAIL through a
    # rollback. A rollback must never leave the host worse than it found it.
    (command -v apt-get >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -y purge "$name" </dev/null) ||
    (command -v dnf >/dev/null && dnf -y remove "$name" </dev/null) || true
  elif [ "$state" = installed ] && [ "$want" = remove ]; then
    (command -v apt-get >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -y install "$name" </dev/null) ||
    (command -v dnf >/dev/null && dnf -y install "$name" </dev/null) || true
  fi
done < pkgs.txt
# a package pulled in as a DEPENDENCY of one we removed (sssd-common dragged in ldap-utils) is not
# removed with it, and it re-fails the control that demands its absence.
(command -v apt-get >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get -y autoremove --purge </dev/null) ||
(command -v dnf >/dev/null && dnf -y autoremove </dev/null) || true
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
	hardenRollbackCmd.Flags().StringVar(&rbTarget, "target", "", "restore to this host instead of the one recorded in the manifest (e.g. a clone)")
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
	if rbTarget != "" {
		target = rbTarget // restore to a different host (e.g. a clone) than the one captured
	}

	// Integrity gate: the tarball is about to be extracted AS ROOT with `tar -P -C /` on the target.
	// Refuse it unless it still hashes to what we recorded at capture. An empty recorded hash means
	// the restore point predates this check; warn rather than block so old restore points still work.
	tarPath := filepath.Join(dir, "restore-point.tar.gz")
	if rp.ArchiveSHA256 != "" {
		sum, _, err := sha256File(tarPath)
		if err != nil {
			return fmt.Errorf("hash restore point archive: %w", err)
		}
		if sum != rp.ArchiveSHA256 {
			return fmt.Errorf("restore point integrity check FAILED: %s does not match the hash in manifest.json "+
				"(expected %s, got %s); refusing to extract it as root", tarPath, rp.ArchiveSHA256, sum)
		}
	} else {
		_, _ = fmt.Fprintln(os.Stderr, "pavois: warning: this restore point has no recorded archive hash (captured "+
			"before integrity checks); its contents cannot be verified before extraction")
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
	_, _ = fmt.Fprintln(os.Stderr, "pavois: shipping the restore point back…")
	// -O: the legacy SCP protocol, over an exec channel. Modern scp speaks SFTP by default,
	// and a stock debian13 (OpenSSH 10) declares no `Subsystem sftp`, so an sftp transfer dies
	// with "subsystem request failed on channel 0", measured on a fresh VM. -O needs no
	// subsystem and works on every target we support.
	scp := exec.Command("scp", append(append([]string{"-O"}, append(opts, tarPath)...), target+":/tmp/pavois-restore-point.tar.gz")...) //nolint:gosec // fixed args
	scp.Stdout, scp.Stderr = os.Stderr, os.Stderr
	if err := scp.Run(); err != nil {
		return fmt.Errorf("copy restore point: %w", err)
	}

	// the wanted actions travel with the restore: it must know which direction to undo each package
	var want strings.Builder
	for _, p := range rp.Packages {
		want.WriteString(p.Name + " " + p.Action + "\n")
	}
	script := "set -u\nrm -rf /tmp/pavois-rp && mkdir -p /tmp/pavois-rp\n" +
		"tar xzf /tmp/pavois-restore-point.tar.gz -C /tmp/pavois-rp\n" +
		"cat > /tmp/pavois-rp/pkgs.want.txt <<'PAVOIS_WANT'\n" + want.String() + "PAVOIS_WANT\n" +
		restoreScript
	if err := runScriptAsRoot(target, opts, sudoPass, script, "pavois-restore.sh"); err != nil {
		return fmt.Errorf("rollback: %w", err)
	}
	_, _ = fmt.Fprintf(out, "\npavois: rolled back. Re-scan to confirm: pavois scan %s --sudo\n", target)
	return nil
}

// presentFromArchive reads present.txt out of the captured tarball: the list of files that DID
// exist before the apply, as recorded ON the target by root.
func presentFromArchive(path string) (map[string]bool, error) {
	f, err := os.Open(path) //nolint:gosec // operator-provided restore point
	if err != nil {
		return nil, err
	}
	defer func() { _ = f.Close() }()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return nil, err
	}
	defer func() { _ = gz.Close() }()
	tr := tar.NewReader(gz)
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil, fmt.Errorf("present.txt not found in the restore point")
		}
		if err != nil {
			return nil, err
		}
		if filepath.Base(h.Name) != "present.txt" {
			continue
		}
		b, err := io.ReadAll(io.LimitReader(tr, 1<<20))
		if err != nil {
			return nil, err
		}
		out := map[string]bool{}
		for _, l := range strings.Split(string(b), "\n") {
			if l = strings.TrimSpace(l); l != "" {
				out[l] = true
			}
		}
		return out, nil
	}
}

// runScriptAsRoot ships a script to the target and runs it under sudo.
//
// It is shipped as a FILE, not piped: `sudo -S bash -s` reads its script from stdin, which is where
// the sudo password has to go, so bash was executing the password and the script never ran. The
// engine already ships its Chef recipe by file for the same reason; so does this.
func runScriptAsRoot(target string, opts []string, sudoPass, script, name string) error {
	f, err := os.CreateTemp("", name)
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(f.Name()) }()
	if _, err := f.WriteString(script); err != nil {
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	remote := "/tmp/" + name
	scp := exec.Command("scp", append(append([]string{"-O"}, append(opts, f.Name())...), target+":"+remote)...) //nolint:gosec // fixed args
	scp.Stderr = os.Stderr
	if err := scp.Run(); err != nil {
		return fmt.Errorf("copy %s: %w", name, err)
	}
	// Draining the password from ssh-stdin into a shell var is what keeps it off argv and out of
	// the pty line discipline. But it must happen ONLY when a password is actually sent: `ssh -tt`
	// allocates a pty on the target, and closing local stdin does not become an EOF there (on a
	// terminal, end-of-input is a ^D character, not a closed stream), so `read` waits for a line
	// that never comes. With no password Go leaves Stdin nil, which is /dev/null, and the whole
	// apply stopped forever right after "photographing the prior state". Measured on Outscale
	// ami-dc3f861d (Debian 12, NOPASSWD, Defaults use_pty).
	remoteCmd := "sudo bash " + remote
	if sudoPass != "" {
		remoteCmd = "IFS= read -r __P; sudo -S bash " + remote + " <<<\"$__P\""
	}
	c := exec.Command("ssh", append(append([]string{"-tt"}, opts...), target, remoteCmd)...) //nolint:gosec // fixed args
	c.Stdout, c.Stderr = os.Stderr, os.Stderr
	if sudoPass != "" {
		c.Stdin = strings.NewReader(sudoPass + "\n")
	}
	return c.Run()
}

// writeRestorePoint captures the prior state and stores it locally, BEFORE the converge runs.
func writeRestorePoint(p planFile, recipe, target, planPath, dir string, opts []string, sudoPass string) (string, error) {
	files, pkgs, svcs, irr := plannedTargets(p, recipe)
	rp := restorePoint{
		Target: target, OS: p.OS, Created: time.Now().UTC().Format(time.RFC3339),
		Plan: filepath.Base(planPath), Files: files, Packages: pkgs, Services: svcs, Irreversible: irr,
	}
	if err := runScriptAsRoot(target, opts, sudoPass, captureScript(rp), "pavois-capture.sh"); err != nil {
		return "", fmt.Errorf("capture prior state: %w", err)
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	fetch := exec.Command("scp", append(append([]string{"-O"}, append(opts, target+":/tmp/pavois-restore-point.tar.gz")...), //nolint:gosec // fixed args
		filepath.Join(dir, "restore-point.tar.gz"))...)
	fetch.Stderr = os.Stderr
	if err := fetch.Run(); err != nil {
		return "", fmt.Errorf("fetch restore point: %w", err)
	}
	// Which files actually existed: a rollback DELETES the ones pavois created, so getting this
	// wrong is the difference between restoring /etc/audit/auditd.conf and deleting it. Read it from
	// the archive we just fetched: NOT by cat'ing it over ssh: root wrote that directory with
	// umask 077, so the unprivileged account we connect with reads nothing, every file comes back
	// "did not exist", and the manifest tells the operator we are about to delete 45 config files.
	existing, err := presentFromArchive(filepath.Join(dir, "restore-point.tar.gz"))
	if err != nil {
		return "", fmt.Errorf("read the captured file list: %w", err)
	}
	for i := range rp.Files {
		rp.Files[i].Existed = existing[rp.Files[i].Path]
	}
	// Record the archive hash so the rollback can prove the tarball it extracts as root is the one
	// we captured, not something that replaced it in restore-points/ since.
	if sum, _, err := sha256File(filepath.Join(dir, "restore-point.tar.gz")); err == nil {
		rp.ArchiveSHA256 = sum
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
