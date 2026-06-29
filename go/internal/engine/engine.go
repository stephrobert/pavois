// Package engine exécute CINC Auditor (build open source d'InSpec) en natif de
// préférence, conteneur en repli. Port de pavois/engine.py — le moteur reste
// 100% CINC/InSpec (jamais oscap), audit de la config EFFECTIVE.
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
)

var (
	reProgCount = regexp.MustCompile(`\[\s*(\d+)\s*/\s*(\d+)\s*\]`) // tolère le padding [  1/359]
	reProgCtrl  = regexp.MustCompile(`\[(?:PASSED|FAILED|SKIPPED)\]\s+(\S+)\s*(.*)`)
)

var reDomain = regexp.MustCompile(`tag domain: '([^']+)'`)

// domainMap lit le profil et associe chaque ID de contrôle à son domaine
// (`tag domain:`) — pour afficher une progression LISIBLE (par domaine) plutôt
// que l'ID brut. Vide si le profil n'est pas un dossier local (URL).
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

// runCinc exécute cinc et rend une PROGRESSION riche sur stderr (N/M, %, contrôle
// courant) en parsant le reporter `progress-bar` — sans déverser les centaines de
// lignes PASSED/FAILED. stdout reste propre. En non-TTY (CI/pipe), une ligne simple.
func runCinc(cmd *exec.Cmd, label string, dmap map[string]string) error {
	fi, _ := os.Stderr.Stat()
	if fi == nil || fi.Mode()&os.ModeCharDevice == 0 {
		_, _ = fmt.Fprintf(os.Stderr, "  %s…\n", label) // non-TTY (CI/pipe) : une ligne, sortie cinc capturée
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
	// La PROGRESSION de cinc (reporter progress-bar : [N/M], PASSED/FAILED) sort sur
	// STDERR. On la PARSE pour rendre notre ligne propre, et on capture le brut pour
	// le montrer en cas de vraie erreur. stdout (json -> fichier) est capturé à part.
	stderrPipe, err := cmd.StderrPipe()
	if err != nil {
		return err
	}
	var outBuf, errBuf bytes.Buffer
	cmd.Stdout = &outBuf
	if err := cmd.Start(); err != nil {
		return err
	}
	// Un goroutine lit la progression ; un ticker anime le spinner en CONTINU (même
	// pendant la connexion / le chargement, avant le 1er contrôle) -> jamais bloqué.
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
	// exit 100/101 = des contrôles échouent (normal) ; sinon vraie erreur -> on
	// remonte la sortie d'erreur capturée de cinc.
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

// Detect interroge la CIBLE (local/ssh/docker) via `cinc-auditor detect` et
// retourne le nom d'OS et la release (ex. "ubuntu","24.04") — pour choisir
// automatiquement le bon profil. Vide si indéterminable.
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

// AuditorImage : image CINC épinglée par digest (repli docker).
const AuditorImage = "cincproject/auditor@sha256:14b1a2efb89ab141adb58e93c6c1bdcf196c9623498a292cbfaee28c46603568"

// NativeBin retourne le binaire CINC natif (cinc-auditor de préférence, sinon inspec).
func NativeBin() string {
	for _, b := range []string{"cinc-auditor", "inspec"} {
		if p, err := exec.LookPath(b); err == nil {
			return p
		}
	}
	return ""
}

// sshAliases lit ~/.ssh/config (et ses Include) et renvoie les alias Host
// explicites (sans joker) — pour reconnaître une cible comme hôte SSH.
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

// IsSSHAlias indique si la cible est un alias Host de ~/.ssh/config.
func IsSSHAlias(target string) bool { return sshAliases()[target] }

// TransportFor déduit le transport CINC de la cible : "" (local), ssh:// (user@hôte
// OU alias ssh_config) ou docker:// (conteneur).
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

// ResolveProfile accepte un nom embarqué (sous profiles/), un chemin ou une URL.
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
	return "", fmt.Errorf("unknown profile: %s (see: pavois profiles)", profile)
}

// Options porte les paramètres d'un scan.
type Options struct {
	Root     string // racine du dépôt (résolution des profils embarqués)
	Target   string // local | user@hôte | conteneur
	Profile  string
	Engine   string // auto | native | docker
	SSHPass  string
	SudoPass string // mot de passe sudo — transmis à cinc via --config (stdin), JAMAIS en argv
	Key      string
	Sudo     bool
	JSONOut  string // chemin du rapport JSON à produire
	Standard string // si défini : n'EXÉCUTE que les contrôles de cette norme
	Level    string // niveau (cumulatif) au sein de la norme, ex. cis:1
	OnTarget bool   // exécuter cinc-auditor SUR la cible (local://) — bien moins
	//                 d'aller-retours SSH, scan beaucoup plus rapide
}

// niveaux ordonnés par norme (cumulatif : un niveau inclut les inférieurs).
var levelOrder = map[string][]string{
	"cis":  {"1", "2"},
	"bp28": {"minimal", "intermediary", "enhanced", "high"},
}

// controlsForNorm liste les IDs de contrôles d'un profil portant le tag de la
// norme (et, si fourni, au niveau cumulatif demandé) — pour ne lancer QUE ceux-là
// via `cinc --controls`. Vide si profil non local (URL) ou norme inconnue.
func controlsForNorm(profDir, standard, level string) []string {
	if standard == "" || standard == "all" {
		return nil
	}
	tagPat := "tag " + regexp.QuoteMeta(standard) + ":"
	if !regexp.MustCompile(`^[a-z0-9_]+$`).MatchString(standard) {
		tagPat = `tag\('` + regexp.QuoteMeta(standard) + `' =>` // ex. pci-dss
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
			if level != "" && maxIdx >= 0 { // filtre de niveau cumulatif
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

// Run exécute le scan et retourne le code de sortie CINC (0 ok, 100/101 échecs).
// secretsConfig builds the JSON for cinc-auditor's `--config -` (read from STDIN),
// carrying the SSH login and/or sudo password. Passing them this way keeps secrets
// OUT of argv — they never appear in `ps`, the process table or any log. Returns ""
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

	// Filtre d'EXÉCUTION par norme : ne lancer que les contrôles taggés (et au
	// niveau demandé) via `cinc --controls <ids…>`. Profil local uniquement.
	var ctlArgs []string
	if fi, err := os.Stat(prof); err == nil && fi.IsDir() {
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
		// progress-bar -> runCinc le parse pour la progression (stderr) ; json ->
		// fichier (pavois produit SA présentation). stdout n'est pas pollué.
		args := []string{"exec", prof, "--no-create-lockfile", "--reporter", "progress-bar", "json:" + o.JSONOut}
		// Expose the active standard to InSpec so a single merged rule can pick the per-norm
		// threshold (e.g. PASS_MIN_LEN >= 15 for bp28, >= 12 for nist). "_default" = strictest.
		std := o.Standard
		if std == "" {
			std = "_default"
		}
		args = append(args, "--input", "pavois_standard="+std)
		args = append(args, ctlArgs...)
		if transport != "" {
			args = append(args, "-t", transport)
			if strings.HasPrefix(transport, "ssh") && strings.Contains(transport, "@") {
				// ssh DIRECT (user@host) : ignorer le ssh_config global (ProxyJump Host *).
				// Pour un ALIAS (sans @), on garde ssh_config pour le résoudre.
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
	runErr := runCinc(cmd, "scanning "+o.Target, dmap) // progression riche sur stderr
	if runErr != nil {
		var ee *exec.ExitError
		if errors.As(runErr, &ee) {
			return ee.ExitCode(), nil // 100/101 = des contrôles échouent, exploitable en CI
		}
		return 2, runErr
	}
	return 0, nil
}

// RunOnTarget runs cinc-auditor ON the target via local:// — every check executes
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
		// -tt forces a pseudo-tty so `sudo` keeps working even under `Defaults requiretty`
		// (ANSSI BP-028 R39, which pavois itself can apply). The report is fetched via scp
		// (a file), so tty CRLF translation never corrupts the parsed output.
		return run("ssh", append(append([]string{"-tt"}, base...), o.Target, remote)...)
	}

	_, _ = fmt.Fprintf(os.Stderr, "  ensuring cinc-auditor on %s…\n", o.Target)
	ensure := "command -v cinc-auditor >/dev/null 2>&1 || command -v inspec >/dev/null 2>&1 || " +
		"curl -L https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc-auditor"
	if err := ssh(ensure); err != nil {
		return 2, fmt.Errorf("ensure cinc-auditor on target: %w", err)
	}

	const remoteProf, remoteJSON = "/tmp/pavois-profile", "/tmp/pavois-out.json"
	_ = ssh("rm -rf " + remoteProf)
	if err := run("scp", append(append([]string{"-r"}, base...), prof, o.Target+":"+remoteProf)...); err != nil {
		return 2, fmt.Errorf("copy profile to target: %w", err)
	}

	sudo := ""
	if o.Sudo {
		sudo = "sudo "
	}
	std := o.Standard
	if std == "" {
		std = "_default" // no standard selected -> the merged rules use their most-secure threshold
	}
	exe := fmt.Sprintf("%senv CHEF_LICENSE=accept-silent $(command -v cinc-auditor || command -v inspec) "+
		"exec %s -t local:// --no-create-lockfile --input pavois_standard=%s --reporter json:%s", sudo, remoteProf, std, remoteJSON)
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
	// cinc-auditor wrote the report as root; on a hardened box (umask 0027) the scp user
	// can't read it. Make it world-readable before fetching (it's a transient report).
	_ = ssh("sudo chmod 0644 " + remoteJSON)
	if err := run("scp", append(append([]string{}, base...), o.Target+":"+remoteJSON, o.JSONOut)...); err != nil {
		return 2, fmt.Errorf("fetch report from target: %w", err)
	}
	return rc, nil
}
