// Package engine runs CINC Auditor (the open source build of InSpec), natively by
// preference, with a container as fallback. Port of pavois/engine.py: the engine
// stays 100% CINC/InSpec (never oscap), auditing the EFFECTIVE config.
package engine

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"pavois/internal/corpus"
)

var (
	reProgCount = regexp.MustCompile(`\[\s*(\d+)\s*/\s*(\d+)\s*\]`) // tolerates padding [  1/359]
	reProgCtrl  = regexp.MustCompile(`\[(?:PASSED|FAILED|SKIPPED)\]\s+(\S+)\s*(.*)`)
)

var reDomain = regexp.MustCompile(`tag domain: '([^']+)'`)

// domainMap reads the profile and maps each control ID to its domain
// (`tag domain:`): to display a READABLE progress (by domain) rather
// than the raw ID. Empty if the profile is not a local directory (URL).
func domainMap(profDir string) map[string]string {
	m := map[string]string{}
	files, _ := filepath.Glob(filepath.Join(profDir, "controls", "*.rb"))
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		for _, chunk := range strings.Split(string(b), "\ncontrol '")[1:] {
			q := strings.IndexByte(chunk, '\'')
			if q < 0 {
				continue
			}
			id := chunk[:q]
			if d := reDomain.FindStringSubmatch(chunk); d != nil {
				m[id] = d[1]
			}
		}
	}
	return m
}

func truncShort(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) <= n {
		return s
	}
	return s[:n-1] + "…"
}

// runCinc runs cinc and renders a rich PROGRESS on stderr (N/M, %, current
// control) by parsing the `progress-bar` reporter: without dumping the hundreds of
// PASSED/FAILED lines. stdout stays clean. In non-TTY (CI/pipe), a single line.
func runCinc(cmd *exec.Cmd, label string, dmap map[string]string) error {
	fi, _ := os.Stderr.Stat()
	if fi == nil || fi.Mode()&os.ModeCharDevice == 0 {
		_, _ = fmt.Fprintf(os.Stderr, "  %s…\n", label) // non-TTY (CI/pipe): one line, cinc output captured
		var buf bytes.Buffer
		cmd.Stdout, cmd.Stderr = &buf, &buf
		err := cmd.Run()
		if err != nil {
			var ee *exec.ExitError
			if !errors.As(err, &ee) || (ee.ExitCode() != 100 && ee.ExitCode() != 101) {
				_, _ = os.Stderr.Write(buf.Bytes())
			}
		}
		return err
	}
	// cinc's PROGRESS (progress-bar reporter: [N/M], PASSED/FAILED) goes to
	// STDERR. We PARSE it to render our own clean line, and capture the raw output
	// to show it on a real error. stdout (json -> file) is captured separately.
	stderrPipe, err := cmd.StderrPipe()
	if err != nil {
		return err
	}
	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	if err := cmd.Start(); err != nil {
		return err
	}
	// A goroutine reads the progress; a ticker animates the spinner CONTINUOUSLY (even
	// during connection / loading, before the 1st control) -> never stuck.
	var mu sync.Mutex
	n, m, cur := 0, 0, "connecting…"
	done := make(chan struct{})
	go func() {
		sc := bufio.NewScanner(stderrPipe)
		sc.Buffer(make([]byte, 64*1024), 1<<20)
		sc.Split(func(data []byte, atEOF bool) (int, []byte, error) {
			for j, b := range data {
				if b == '\n' || b == '\r' {
					return j + 1, data[:j], nil
				}
			}
			if atEOF && len(data) > 0 {
				return len(data), data, nil
			}
			return 0, nil, nil
		})
		for sc.Scan() {
			t := sc.Text()
			mu.Lock()
			errBuf.WriteString(t)
			errBuf.WriteByte('\n')
			if c := reProgCount.FindStringSubmatch(t); c != nil {
				n, _ = strconv.Atoi(c[1])
				m, _ = strconv.Atoi(c[2])
			}
			if c := reProgCtrl.FindStringSubmatch(t); c != nil {
				if d, ok := dmap[c[1]]; ok {
					cur = d
				} else {
					cur = strings.TrimSpace(c[1] + " " + c[2])
				}
			}
			mu.Unlock()
		}
		close(done)
	}()
	frames := []rune("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
	tk := time.NewTicker(90 * time.Millisecond)
	i := 0
spin:
	for {
		select {
		case <-done:
			break spin
		case <-tk.C:
			mu.Lock()
			nn, mm, cc := n, m, cur
			mu.Unlock()
			pct := 0
			if mm > 0 {
				pct = nn * 100 / mm
			}
			i++
			if mm > 0 {
				_, _ = fmt.Fprintf(os.Stderr, "\r\033[K  %c %s  %d/%d (%d%%)  %s",
					frames[i%len(frames)], label, nn, mm, pct, truncShort(cc, 46))
			} else {
				_, _ = fmt.Fprintf(os.Stderr, "\r\033[K  %c %s  %s",
					frames[i%len(frames)], label, cc)
			}
		}
	}
	tk.Stop()
	werr := cmd.Wait()
	_, _ = fmt.Fprint(os.Stderr, "\r\033[K")
	// exit 100/101 = controls are failing (normal); otherwise a real error -> we
	// surface cinc's captured error output.
	if werr != nil {
		code := -1
		var ee *exec.ExitError
		if errors.As(werr, &ee) {
			code = ee.ExitCode()
		}
		if code != 100 && code != 101 {
			_, _ = os.Stderr.Write(errBuf.Bytes())
			_, _ = os.Stderr.Write(outBuf.Bytes())
		}
	}
	return werr
}

// Detect queries the TARGET (local/ssh/docker) via `cinc-auditor detect` and
// returns the OS name and release (e.g. "ubuntu","24.04"): to automatically
// choose the right profile. Empty if undeterminable.
func Detect(o Options) (name, release string) {
	bin := NativeBin()
	if bin == "" {
		return "", ""
	}
	transport := TransportFor(o.Target)
	args := []string{"detect", "--format", "json"}
	if transport != "" {
		args = append(args, "-t", transport)
		if strings.HasPrefix(transport, "ssh") && strings.Contains(transport, "@") {
			args = append(args, "--ssh-config-file", "/dev/null")
		}
	}
	if o.Key != "" {
		args = append(args, "-i", o.Key)
	}
	secret := secretsConfig(o)
	if secret != "" {
		args = append(args, "--config", "-") // SSH password via stdin, not argv
	}
	cmd := exec.Command(bin, args...)
	if secret != "" {
		cmd.Stdin = strings.NewReader(secret)
	}
	cmd.Env = stripSecretEnv(append(os.Environ(), "CHEF_LICENSE=accept-silent"))
	out, err := cmd.Output()
	if err != nil {
		return "", ""
	}
	var d struct {
		Name, Release string
	}
	if json.Unmarshal(out, &d) != nil {
		return "", ""
	}
	return d.Name, d.Release
}

// AuditorImage: CINC image pinned by digest (docker fallback).
const AuditorImage = "cincproject/auditor@sha256:14b1a2efb89ab141adb58e93c6c1bdcf196c9623498a292cbfaee28c46603568"

// waiverFile returns the profile's InSpec waiver file: the ACCEPTED RISKS: controls pavois
// deliberately does not enforce (enforcing them would break the host, or the check is defective),
// each with a justification an auditor can read. Empty when the profile is a URL or has none.
func waiverFile(prof string) string {
	w := filepath.Join(prof, "waivers.yml")
	if fi, err := os.Stat(w); err == nil && !fi.IsDir() {
		return w
	}
	return ""
}

// NativeBin returns the native CINC binary (cinc-auditor by preference, otherwise inspec).
func NativeBin() string {
	for _, b := range []string{"cinc-auditor", "inspec"} {
		if p, err := exec.LookPath(b); err == nil {
			return p
		}
	}
	return ""
}

// sshAliases reads ~/.ssh/config (and its Include) and returns the explicit
// Host aliases (without wildcards): to recognize a target as an SSH host.
func sshAliases() map[string]bool {
	m := map[string]bool{}
	home, err := os.UserHomeDir()
	if err != nil {
		return m
	}
	seen := map[string]bool{}
	var parse func(string)
	parse = func(path string) {
		if seen[path] {
			return
		}
		seen[path] = true
		b, err := os.ReadFile(path) //nolint:gosec // G703: reads ~/.ssh/config and its operator-owned Include paths, not untrusted input (same rationale as the G304 exclusion)
		if err != nil {
			return
		}
		for _, line := range strings.Split(string(b), "\n") {
			f := strings.Fields(strings.TrimSpace(line))
			if len(f) < 2 {
				continue
			}
			switch strings.ToLower(f[0]) {
			case "host":
				for _, h := range f[1:] {
					if !strings.ContainsAny(h, "*?!") {
						m[h] = true
					}
				}
			case "include":
				for _, pat := range f[1:] {
					switch {
					case strings.HasPrefix(pat, "~/"):
						pat = filepath.Join(home, pat[2:])
					case !filepath.IsAbs(pat):
						pat = filepath.Join(home, ".ssh", pat)
					}
					if matches, _ := filepath.Glob(pat); matches != nil {
						for _, mm := range matches {
							parse(mm)
						}
					}
				}
			}
		}
	}
	parse(filepath.Join(home, ".ssh", "config"))
	return m
}

// IsSSHAlias reports whether the target is a Host alias in ~/.ssh/config.
func IsSSHAlias(target string) bool { return sshAliases()[target] }

// TransportFor derives the CINC transport from the target: "" (local), ssh:// (user@host
// OR ssh_config alias) or docker:// (container).
func TransportFor(target string) string {
	switch {
	case target == "local":
		return ""
	case strings.Contains(target, "@"), IsSSHAlias(target):
		return "ssh://" + target
	default:
		return "docker://" + target
	}
}

// ResolveProfile accepts an embedded name (under profiles/), a path or a URL.
func ResolveProfile(root, profile string) (string, error) {
	if strings.HasPrefix(profile, "http://") || strings.HasPrefix(profile, "https://") {
		return profile, nil
	}
	bundled := filepath.Join(root, "profiles", profile)
	if fi, err := os.Stat(bundled); err == nil && fi.IsDir() {
		return bundled, nil
	}
	if _, err := os.Stat(profile); err == nil {
		return profile, nil
	}
	// Fallback: a standalone released binary has no profiles/ on disk but embeds the corpus.
	if dir, ok := corpus.Extract(filepath.Join(os.TempDir(), "pavois-corpus"), profile); ok {
		return dir, nil
	}
	return "", fmt.Errorf("unknown profile: %s (see: pavois profiles)", profile)
}

// Options carries the parameters of a scan.
type Options struct {
	Root     string // repository root (resolution of embedded profiles)
	Target   string // local | user@host | container
	Profile  string
	Engine   string // auto | native | docker
	SSHPass  string
	SudoPass string // sudo password: passed to cinc via --config (stdin), NEVER in argv
	Key      string
	Sudo     bool
	JSONOut  string // path of the JSON report to produce
	Standard string // if set: only RUNS the controls of this standard
	Level    string // level (cumulative) within the standard, e.g. cis:1
	OnTarget bool   // run cinc-auditor ON the target (local://): far fewer
	//                 SSH round-trips, much faster scan
	Controls []string // if set: runs ONLY these controls (by id), via cinc --controls
}

// levels ordered per standard (cumulative: a level includes the lower ones).
var levelOrder = map[string][]string{
	"cis":  {"1", "2"},
	"bp28": {"minimal", "intermediary", "enhanced", "high"},
}

// controlsForNorm lists the control IDs of a profile carrying the standard's
// tag (and, if provided, at the requested cumulative level): to run ONLY those
// via `cinc --controls`. Empty if the profile is not local (URL) or the standard is unknown.
func controlsForNorm(profDir, standard, level string) []string {
	if standard == "" || standard == "all" {
		return nil
	}
	tagPat := "tag " + regexp.QuoteMeta(standard) + ":"
	if !regexp.MustCompile(`^[a-z0-9_]+$`).MatchString(standard) {
		tagPat = `tag\('` + regexp.QuoteMeta(standard) + `' =>` // e.g. pci-dss
	}
	reTag := regexp.MustCompile(tagPat)
	reLvl := regexp.MustCompile(`tag level_` + strings.ReplaceAll(standard, "-", "_") + `: '([^']+)'`)
	order := levelOrder[standard]
	maxIdx := -1
	for i, l := range order {
		if l == level {
			maxIdx = i
		}
	}
	var ids []string
	files, _ := filepath.Glob(filepath.Join(profDir, "controls", "*.rb"))
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		for _, ch := range strings.Split(string(b), "\ncontrol '")[1:] {
			q := strings.IndexByte(ch, '\'')
			if q < 0 {
				continue
			}
			id := ch[:q]
			block := ch
			if e := strings.Index(ch, "\nend\n"); e >= 0 {
				block = ch[:e]
			}
			if !reTag.MatchString(block) {
				continue
			}
			if level != "" && maxIdx >= 0 { // cumulative level filter
				lm := reLvl.FindStringSubmatch(block)
				if lm != nil {
					li := -1
					for i, l := range order {
						if l == lm[1] {
							li = i
						}
					}
					if li > maxIdx {
						continue
					}
				}
			}
			ids = append(ids, id)
		}
	}
	return ids
}

// Run runs the scan and returns the CINC exit code (0 ok, 100/101 failures).
// secretsConfig builds the JSON for cinc-auditor's `--config -` (read from STDIN),
// carrying the SSH login and/or sudo password. Passing them this way keeps secrets
// OUT of argv: they never appear in `ps`, the process table or any log. Returns ""
// when there is no secret (the caller then omits --config and stdin).
func secretsConfig(o Options) string {
	cfg := map[string]string{}
	if o.SSHPass != "" {
		cfg["password"] = o.SSHPass
	}
	if o.SudoPass != "" {
		cfg["sudo_password"] = o.SudoPass
	}
	if len(cfg) == 0 {
		return ""
	}
	b, _ := json.Marshal(cfg)
	return string(b)
}

// stripSecretEnv removes pavois's password env vars from the environment handed to
// cinc-auditor, so a password supplied via PAVOIS_SUDO_PASSWORD / PAVOIS_SSH_PASSWORD
// is never exposed in the child process's /proc/<pid>/environ (or inherited further).
func stripSecretEnv(env []string) []string {
	out := make([]string, 0, len(env))
	for _, e := range env {
		if strings.HasPrefix(e, "PAVOIS_SUDO_PASSWORD=") || strings.HasPrefix(e, "PAVOIS_SSH_PASSWORD=") {
			continue
		}
		out = append(out, e)
	}
	return out
}

// auditArgs are the arguments EVERY engine must pass, whatever the transport.
//
// They were previously written inline in the native branch only, and the docker branch: which
// builds its own argument list: silently lacked both. That is not a cosmetic drift: without the
// waiver file the project's own accepted risks come back as plain failures (the grade is wrong and
// the report tells the operator to apply a remediation pavois deliberately refuses to ship), and
// without the input every merged rule falls back to `_default`, so `--standard cis` quietly grades
// against the strictest threshold instead of the CIS one. A wrong verdict is worse than a missing
// one, so the shared arguments live here, once.
//
// profPath is the profile as the ENGINE sees it: the host path natively, /profile inside the
// container. waiverPath is resolved on the host either way, since that is where the file is read.
func auditArgs(profPath, waiverPath, standard string) []string {
	var args []string
	// Accepted risks: a control we deliberately do not enforce (enforcing it would break the
	// host, or the check itself is defective) is listed in the profile's waivers.yml with a
	// justification. cinc SKIPS it instead of failing it, and the justification rides along in
	// the report: an auditable exception rather than a permanent red mark.
	if waiverPath != "" {
		args = append(args, "--waiver-file", profPath+"/waivers.yml")
	}
	// Expose the active standard to InSpec so a single merged rule can pick the per-norm
	// threshold (e.g. PASS_MIN_LEN >= 15 for bp28, >= 12 for nist). "_default" = strictest.
	if standard == "" {
		standard = "_default"
	}
	return append(args, "--input", "pavois_standard="+standard)
}

func Run(o Options) (int, error) {
	if o.OnTarget {
		return RunOnTarget(o)
	}
	prof, err := ResolveProfile(o.Root, o.Profile)
	if err != nil {
		return 2, err
	}
	transport := TransportFor(o.Target)
	bin := NativeBin()
	eng := o.Engine
	if eng == "auto" {
		if bin != "" {
			eng = "native"
		} else {
			eng = "docker"
		}
	}
	if o.Target == "local" && eng != "native" {
		return 2, fmt.Errorf("target 'local' cannot run via container (it would audit itself); install cinc-auditor")
	}
	_ = os.Remove(o.JSONOut)

	// EXECUTION filter by standard: run only the tagged controls (and at the
	// requested level) via `cinc --controls <ids…>`. Local profile only.
	var ctlArgs []string
	if len(o.Controls) > 0 {
		// Explicit control ids (e.g. `pavois scan --controls ssh-disable-root-login`):
		// run ONLY those, for a fast single-rule iteration loop.
		ctlArgs = append([]string{"--controls"}, o.Controls...)
	} else if fi, err := os.Stat(prof); err == nil && fi.IsDir() {
		if ids := controlsForNorm(prof, o.Standard, o.Level); len(ids) > 0 {
			ctlArgs = append([]string{"--controls"}, ids...)
		}
	}
	env := append(os.Environ(), "CHEF_LICENSE=accept-silent")
	secret := secretsConfig(o) // secrets -> cinc via stdin (--config -), never argv

	var cmd *exec.Cmd
	if eng == "native" {
		if bin == "" {
			return 2, fmt.Errorf("native engine missing: install cinc-auditor or use --engine docker")
		}
		// progress-bar -> runCinc parses it for progress (stderr); json ->
		// file (pavois produces ITS OWN presentation). stdout is not polluted.
		args := []string{"exec", prof, "--no-create-lockfile", "--reporter", "progress-bar", "json:" + o.JSONOut}
		args = append(args, auditArgs(prof, waiverFile(prof), o.Standard)...)
		args = append(args, ctlArgs...)
		if transport != "" {
			args = append(args, "-t", transport)
			if strings.HasPrefix(transport, "ssh") && strings.Contains(transport, "@") {
				// DIRECT ssh (user@host): ignore the global ssh_config (ProxyJump Host *).
				// For an ALIAS (without @), we keep ssh_config to resolve it.
				args = append(args, "--ssh-config-file", "/dev/null")
			}
		}
		if secret != "" {
			args = append(args, "--config", "-") // SSH/sudo passwords via stdin, not argv
		}
		if o.Key != "" {
			args = append(args, "-i", o.Key)
		}
		if o.Sudo {
			args = append(args, "--sudo")
		}
		cmd = exec.Command(bin, args...)
	} else {
		docker, err := exec.LookPath("docker")
		if err != nil {
			return 2, fmt.Errorf("docker not found")
		}
		args := []string{"run", "--rm"}
		if secret != "" {
			args = append(args, "-i") // attach stdin so cinc can read --config -
		}
		if strings.HasPrefix(transport, "ssh") {
			args = append(args, "--network", "host")
		}
		args = append(args, "-e", "CHEF_LICENSE=accept-silent",
			"-v", "/var/run/docker.sock:/var/run/docker.sock",
			"-v", docker+":/usr/bin/docker:ro",
			"-v", filepath.Dir(o.JSONOut)+":/out")
		profArg := prof
		if fi, err := os.Stat(prof); err == nil && fi.IsDir() {
			args = append(args, "-v", prof+":/profile:ro")
			profArg = "/profile"
		}
		if o.Key != "" {
			args = append(args, "-v", o.Key+":/key:ro")
		}
		tgt := transport
		if tgt == "" {
			tgt = "docker://"
		}
		args = append(args, AuditorImage, "exec", profArg, "-t", tgt,
			"--no-create-lockfile", "--reporter", "progress-bar", "json:/out/"+filepath.Base(o.JSONOut))
		// The waiver file is read by cinc INSIDE the container, so it is named by the mounted
		// path (profArg), not the host one: but its existence is checked on the host.
		args = append(args, auditArgs(profArg, waiverFile(prof), o.Standard)...)
		args = append(args, ctlArgs...)
		if secret != "" {
			args = append(args, "--config", "-") // SSH/sudo passwords via stdin, not argv
		}
		if o.Key != "" {
			args = append(args, "-i", "/key")
		}
		if o.Sudo {
			args = append(args, "--sudo")
		}
		cmd = exec.Command(docker, args...)
		env = os.Environ()
	}

	if secret != "" {
		cmd.Stdin = strings.NewReader(secret) // cinc reads --config - here
	}
	cmd.Env = stripSecretEnv(env) // never hand the password to the child's environment
	dmap := map[string]string{}
	if fi, err := os.Stat(prof); err == nil && fi.IsDir() {
		dmap = domainMap(prof)
	}
	runErr := runCinc(cmd, "scanning "+o.Target, dmap) // rich progress on stderr
	if runErr != nil {
		var ee *exec.ExitError
		if errors.As(runErr, &ee) {
			return ee.ExitCode(), nil // 100/101 = controls are failing, usable in CI
		}
		return 2, runErr
	}
	return 0, nil
}

// RunOnTarget runs cinc-auditor ON the target via local://: every check executes
// locally instead of as an SSH command round-trip, which is dramatically faster for
// large profiles. cinc-auditor is installed on the target if missing (omnitruck).
func RunOnTarget(o Options) (int, error) {
	prof, err := ResolveProfile(o.Root, o.Profile)
	if err != nil {
		return 2, err
	}
	if !strings.Contains(o.Target, "@") {
		return 2, fmt.Errorf("--on-target needs an ssh target (user@host)")
	}
	base := []string{"-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=20", "-F", "/dev/null"}
	if o.Key != "" {
		base = append(base, "-i", o.Key)
	}
	run := func(name string, a ...string) error {
		c := exec.Command(name, a...)
		c.Stderr = os.Stderr
		return c.Run()
	}
	ssh := func(remote string) error {
		// A hardened target has `Defaults use_pty`, which needs a controlling tty (-tt) or sudo dies
		// with "a password is required"; but `ssh -tt` + a naked piped password races the pty line
		// discipline and sudo times out. So when we have a password: force -tt AND drain it from
		// ssh-stdin into a shell var first, feeding sudo via a bash here-string (no race, off argv).
		// With no password (NOPASSWD) skip -tt entirely.
		args := append(append([]string{}, base...), o.Target, remote)
		if o.Sudo && o.SudoPass != "" {
			wrapped := "IFS= read -r __P; " + remote + " <<<\"$__P\""
			args = append(append([]string{"-tt"}, base...), o.Target, wrapped)
		}
		c := exec.Command("ssh", args...)
		c.Stderr = os.Stderr
		if o.Sudo && o.SudoPass != "" {
			c.Stdin = strings.NewReader(o.SudoPass + "\n")
		}
		return c.Run()
	}

	_, _ = fmt.Fprintf(os.Stderr, "  ensuring cinc-auditor on %s…\n", o.Target)
	// FIRST check presence with NO sudo: cinc-auditor is world-executable in PATH, and a hardened
	// target (use_pty) blocks a naked non-tty sudo, so we must never need sudo just to CHECK (that
	// broke the post-harden re-scan). Only if it is genuinely absent do we sudo-install it.
	checkArgs := append(append([]string{}, base...), o.Target, "command -v cinc-auditor >/dev/null 2>&1 || command -v inspec >/dev/null 2>&1")
	if exec.Command("ssh", checkArgs...).Run() != nil { //nolint:gosec // fixed args, operator target
		ensureSudo := "sudo "
		if o.SudoPass != "" {
			ensureSudo = "sudo -S "
		}
		// Install AS ROOT, downloading the installer to a FILE then running it (a `curl | bash` pipe
		// or a nested `sudo bash` wedges on the target). Runs over ssh WITHOUT -tt and pipes the
		// password: `ssh -tt` + stdin races the pty line discipline and `sudo -S` times out on rhel9;
		// a plain pipe to sudo -S is reliable and the fresh (not-yet-hardened) target has no use_pty
		// yet. The password never reaches argv. cinc-auditor absent -> pavois installs it itself.
		install := ensureSudo + "sh -c 'curl -fsSL https://omnitruck.cinc.sh/install.sh -o /tmp/pavois-cinc-install.sh && sh /tmp/pavois-cinc-install.sh -P cinc-auditor'"
		instArgs := append(append([]string{}, base...), o.Target, install)
		ec := exec.Command("ssh", instArgs...) //nolint:gosec // fixed args, operator target
		ec.Stdout, ec.Stderr = os.Stderr, os.Stderr
		if o.Sudo && o.SudoPass != "" {
			ec.Stdin = strings.NewReader(o.SudoPass + "\n")
		}
		if err := ec.Run(); err != nil {
			return 2, fmt.Errorf("ensure cinc-auditor on target: %w", err)
		}
	}

	const remoteProf, remoteJSON = "/tmp/pavois-profile", "/tmp/pavois-out.json"
	_ = ssh("rm -rf " + remoteProf)
	if err := run("scp", append(append([]string{"-r"}, base...), prof, o.Target+":"+remoteProf)...); err != nil {
		return 2, fmt.Errorf("copy profile to target: %w", err)
	}

	sudo := ""
	if o.Sudo {
		sudo = "sudo "
		if o.SudoPass != "" {
			sudo = "sudo -S " // read the password (piped to ssh stdin above), not NOPASSWD
		}
	}
	std := o.Standard
	if std == "" {
		std = "_default" // no standard selected -> the merged rules use their most-secure threshold
	}
	// HOME is forced to a scratch dir: sudo keeps the caller's HOME, so cinc (running as root)
	// creates a root-owned ~/.inspec in the audited user's home. An auditor must leave NO trace on
	// the target, and pavois was failing its own home-files-permissions control on that garbage.
	const remoteHome = "/tmp/pavois-home"
	cincCmd := fmt.Sprintf("env HOME=%s CHEF_LICENSE=accept-silent $(command -v cinc-auditor || command -v inspec) "+
		"exec %s -t local:// --no-create-lockfile --input pavois_standard=%s --reporter json:%s",
		remoteHome, remoteProf, std, remoteJSON)
	// Accepted risks travel with the profile (the whole dir is copied), so point cinc at the copy.
	if waiverFile(prof) != "" {
		cincCmd += " --waiver-file " + remoteProf + "/waivers.yml"
	}
	if len(o.Controls) > 0 { // single-rule iteration: run only these controls
		cincCmd += " --controls " + strings.Join(o.Controls, " ")
	}
	// cinc-auditor must NOT inherit the -tt pty as stdin: on some targets (rhel9) train-local goes
	// interactive on a tty and hangs, producing no report. `sudo -S` still reads the password from
	// the pty, then the scan runs under `sh -c` with stdin on /dev/null. cincCmd has no single quotes.
	exe := sudo + "sh -c '" + cincCmd + " </dev/null'"
	// Drop any report left by a previous run FIRST: cinc writes it as root in the sticky /tmp, so
	// only root can remove it. Without this, a scan that dies before writing (bad profile, cinc
	// error) silently ships the STALE report back and pavois reports someone else's results.
	_ = ssh(sudo + "rm -f " + remoteJSON)
	_, _ = fmt.Fprintf(os.Stderr, "  scanning %s on the target (local, fast)…\n", o.Target)
	rc := 0
	if err := ssh(exe); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			rc = ee.ExitCode() // 100/101 = failing controls, fine
		} else {
			return 2, err
		}
	}
	if rc != 0 && rc != 100 && rc != 101 { // anything else = cinc itself failed, there is no report
		return 2, fmt.Errorf("cinc-auditor failed on the target (exit %d): no report produced", rc)
	}
	// cinc-auditor wrote the report as root; on a hardened box (umask 0027) the scp user
	// can't read it. Make it world-readable before fetching (it's a transient report).
	_ = ssh(sudo + "chmod 0644 " + remoteJSON)
	if err := run("scp", append(append([]string{}, base...), o.Target+":"+remoteJSON, o.JSONOut)...); err != nil {
		return 2, fmt.Errorf("fetch report from target: %w", err)
	}
	// Leave no trace: the profile copy, the report and the scratch HOME are ours, not the target's.
	// (Older pavois versions left a root-owned ~/.inspec behind; remove that too.)
	_ = ssh(sudo + "rm -rf " + remoteProf + " " + remoteJSON + " " + remoteHome + " ~/.inspec")
	return rc, nil
}
