package cmd

import (
	"bufio"
	crand "crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"

	"pavois/internal/audit"
	"pavois/internal/engine"
	"pavois/internal/render"
)

// harden carries the remediation flow. `plan` is its first, read-only step: scan
// the target, read the Pavois reference (which OWNS the remediation knowledge),
// and emit a STATE-AWARE hardening plan the user opts into rule by rule.
var hardenCmd = &cobra.Command{
	Use:   "harden",
	Short: "Plan and apply hardening from the Pavois reference (Chef-native, no bash)",
	Long: "Drive hardening from a state-aware YAML plan. `pavois harden plan <target>`\n" +
		"scans the machine, reads the Pavois reference, and writes a plan where already-\n" +
		"compliant rules are shown (never re-applied) and only real gaps are opt-in.",
}

var (
	hdFrom       string
	hdKey        string
	hdSSHPass    string
	hdSSHPrompt  bool
	hdSudo       bool
	hdSudoPrompt bool
	hdEngine     string
	hdOut        string
)

var hardenPlanCmd = &cobra.Command{
	Use:   "plan <target>",
	Short: "Scan a target and write a state-aware hardening plan (YAML)",
	Args:  cobra.ExactArgs(1),
	RunE:  runHardenPlan,
}

var (
	haKey      string
	haTarget   string
	haDryRun   bool
	haYes      bool
	haScan     bool
	haReboot   bool
	haStandard string

	haSudoPrompt        bool
	haRestorePoint      string
	haNoRestorePoint    bool
	haIUnderstandDanger bool
)

var hardenApplyCmd = &cobra.Command{
	Use:   "apply <plan.yml>",
	Short: "Compile the enabled plan items into a native Chef run and converge the target",
	Args:  cobra.ExactArgs(1),
	RunE:  runHardenApply,
}

func init() {
	hardenPlanCmd.Flags().StringVar(&hdFrom, "from", "", "use an existing InSpec scan JSON instead of scanning")
	hardenPlanCmd.Flags().StringVar(&hdKey, "key", "", "SSH private key for the target")
	hardenPlanCmd.Flags().StringVar(&hdSSHPass, "ssh-pass", "", "SSH password (discouraged: leaks via ps/history; prefer --ssh-prompt or a key)")
	hardenPlanCmd.Flags().BoolVar(&hdSSHPrompt, "ssh-prompt", false, "prompt for the SSH password (no echo; also reads PAVOIS_SSH_PASSWORD)")
	hardenPlanCmd.Flags().BoolVar(&hdSudo, "sudo", false, "run checks with sudo (needed for effective config)")
	hardenPlanCmd.Flags().BoolVar(&hdSudoPrompt, "sudo-prompt", false, "prompt for the sudo password (no echo; also reads PAVOIS_SUDO_PASSWORD); implies --sudo")
	hardenPlanCmd.Flags().StringVar(&hdEngine, "engine", "auto", "cinc engine: auto|native|docker")
	hardenPlanCmd.Flags().StringVar(&hdOut, "out", "", "plan output path (default: ./hardening-plan-<os>.yml)")
	hardenCmd.AddCommand(hardenPlanCmd)

	hardenApplyCmd.Flags().StringVar(&haKey, "key", "", "SSH private key for the target")
	hardenApplyCmd.Flags().StringVar(&haTarget, "target", "", "override the target from the plan")
	hardenApplyCmd.Flags().BoolVar(&haDryRun, "dry-run", false, "compile and print the Chef recipe, do not converge")
	hardenApplyCmd.Flags().BoolVar(&haYes, "yes", false, "skip the confirmation prompt (CI / --auto-approve)")
	hardenApplyCmd.Flags().BoolVar(&haScan, "scan", false, "after converging, re-scan and generate a fresh report + grade")
	hardenApplyCmd.Flags().BoolVar(&haReboot, "reboot", false, "when changes need it, reboot the target via a Chef `reboot` resource at the end of the run")
	hardenApplyCmd.Flags().StringVar(&haStandard, "standard", "", "apply each rule's value for THIS standard (bp28|cis|nist|…); default = the most-secure value")
	hardenApplyCmd.Flags().BoolVar(&haSudoPrompt, "sudo-prompt", false, "prompt for the sudo password (no echo; also reads PAVOIS_SUDO_PASSWORD): for a least-privilege target account without NOPASSWD")
	hardenApplyCmd.Flags().StringVar(&haRestorePoint, "restore-point", "", "where to write the restore point (default: restore-points/<target>-<timestamp>)")
	hardenApplyCmd.Flags().BoolVar(&haNoRestorePoint, "no-restore-point", false, "do NOT photograph the prior state before converging (you lose `harden rollback`)")
	hardenApplyCmd.Flags().BoolVar(&haIUnderstandDanger, "i-understand-danger", false, "acknowledge ALL `danger:` items at once (brick/lockout risk); otherwise set `acknowledged: true` per item in the plan")
	hardenCmd.AddCommand(hardenApplyCmd)

	rootCmd.AddCommand(hardenCmd)
}

// --- InSpec scan JSON (only what we need: per-control result status) ---
type inspecScan struct {
	Profiles []struct {
		Controls []struct {
			ID      string `json:"id"`
			Title   string `json:"title"`
			Results []struct {
				Status string `json:"status"`
			} `json:"results"`
		} `json:"controls"`
	} `json:"profiles"`
}

// --- Pavois reference (only the fields the plan needs) ---
type refControl struct {
	Domain          string         `yaml:"domain"`
	Title           string         `yaml:"title"`
	Severity        string         `yaml:"severity"`
	Remediation     map[string]any `yaml:"remediation"`
	RequiresPackage string         `yaml:"requires_package"`
	Danger          string         `yaml:"danger"`
	Class           string         `yaml:"remediation_class"`
}
type refDoc struct {
	Rules map[string]refControl `yaml:"rules"`
}

type planRule struct {
	Title           string         `yaml:"title"`
	Domain          string         `yaml:"domain"`
	Severity        string         `yaml:"severity"`
	Status          string         `yaml:"status"`
	Danger          string         `yaml:"danger,omitempty"`       // brick/lockout risk, shown before apply
	Class           string         `yaml:"class,omitempty"`        // non-auto: a recipe/rebuild the apply cannot run (install-time, kernel-build, manual)
	Acknowledged    *bool          `yaml:"acknowledged,omitempty"` // must be flipped true (or --i-understand-danger) to apply a danger item
	Apply           *bool          `yaml:"apply,omitempty"`
	Choose          *string        `yaml:"choose,omitempty"`
	Remediation     map[string]any `yaml:"remediation,omitempty"`
	ActivatedBy     string         `yaml:"activated_by,omitempty"`
	RequiresPackage string         `yaml:"requires_package,omitempty"`
}
type baselinePkg struct {
	Name      string `yaml:"name"`
	Activates int    `yaml:"activates"`
	Apply     bool   `yaml:"apply"`
}

func controlStatus(results []struct {
	Status string `json:"status"`
}) string {
	if len(results) == 0 {
		return "not_applicable"
	}
	allSkipped := true
	for _, r := range results {
		if r.Status == "failed" {
			return "gap"
		}
		if r.Status != "skipped" {
			allSkipped = false
		}
	}
	if allSkipped {
		return "not_applicable"
	}
	return "compliant"
}

func runHardenPlan(cmd *cobra.Command, args []string) error {
	root := findRoot()
	target := args[0]
	_, transport := machineTransport(target)

	// Resolve secrets up front and drop them from our env (no child inherits them);
	// they reach cinc only over stdin (--config -), never argv.
	sudo := hdSudo || hdSudoPrompt
	sudoPass, err := resolveSudoPass(hdSudoPrompt)
	if err != nil {
		return fmt.Errorf("read sudo password: %w", err)
	}
	sshPass, err := resolveSSHPass(hdSSHPass, hdSSHPrompt)
	if err != nil {
		return fmt.Errorf("read SSH password: %w", err)
	}

	// Detect the target OS to pick the right reference (no asking the user).
	_, _ = fmt.Fprint(os.Stderr, "  ⠿ detecting target OS…\r")
	prof, detected := detectProfile(root, engine.Options{Target: target, Key: hdKey, SSHPass: sshPass})
	_, _ = fmt.Fprint(os.Stderr, "\033[K")
	if prof == "" {
		return fmt.Errorf("could not detect a Pavois profile for target %q (%s)", target, detected)
	}
	osName := strings.TrimPrefix(prof, "linux/")
	_, _ = fmt.Fprintf(os.Stderr, "pavois: detected %s → reference %s\n", detected, osName)

	// Scan (or reuse an existing JSON).
	jsonPath := hdFrom
	if jsonPath == "" {
		_ = os.MkdirAll(filepath.Join(root, "reports"), 0o750)
		jsonPath = filepath.Join(root, "reports", fmt.Sprintf("harden-scan-%s-%s.json",
			osName, time.Now().Format("20060102-150405")))
		if _, err := engine.Run(engine.Options{
			Root: root, Target: target, Profile: prof, Engine: hdEngine,
			SSHPass: sshPass, SudoPass: sudoPass, Key: hdKey, Sudo: sudo, JSONOut: jsonPath,
			// scan ON the target: fewer round-trips AND robust to a hardened box (the
			// SSH-transport scan breaks under Defaults requiretty/noexec). On-target sudo
			// assumes NOPASSWD, so when a sudo password is supplied we use the native SSH
			// transport instead (it feeds the password to cinc over stdin).
			OnTarget: strings.Contains(target, "@") && sudoPass == "",
		}); err != nil {
			return err
		}
	}

	// Parse scan + reference.
	scanRaw, err := os.ReadFile(jsonPath)
	if err != nil {
		return err
	}
	var scan inspecScan
	if err := json.Unmarshal(scanRaw, &scan); err != nil {
		return fmt.Errorf("parse scan JSON: %w", err)
	}
	refRaw, err := os.ReadFile(filepath.Join(root, "docs", "reference", "pavois-content", osName+".yml"))
	if err != nil {
		return fmt.Errorf("read reference: %w", err)
	}
	var ref refDoc
	if err := yaml.Unmarshal(refRaw, &ref); err != nil {
		return fmt.Errorf("parse reference: %w", err)
	}

	// Build the state-aware plan.
	rules := map[string]planRule{}
	counts := map[string]int{"compliant": 0, "gap": 0, "not_applicable": 0}
	baseline := map[string]int{}
	for _, p := range scan.Profiles {
		for _, c := range p.Controls {
			e := ref.Rules[c.ID]
			st := controlStatus(c.Results)
			counts[st]++
			pr := planRule{Title: e.Title, Domain: e.Domain, Severity: e.Severity, Status: st}
			if pr.Title == "" {
				pr.Title = c.Title
			}
			pr.RequiresPackage = e.RequiresPackage // dependency: install this prereq when applied
			pr.Danger = e.Danger                   // brick/lockout risk surfaced before the operator opts in
			if e.Class != "" && e.Class != "auto" {
				// install-time / kernel-build / manual: no apply can close this gap: it takes a
				// recipe or a rebuild. Saying so keeps a convergence loop from re-enabling it
				// every pass and never reaching a fixpoint.
				pr.Class = e.Class
			}
			switch st {
			case "gap", "compliant":
				// Carry the remediation for BOTH: gaps need fixing, and a control that's
				// compliant only by OS-default luck must stay enforceable so Pavois can
				// re-assert it if it drifts. apply defaults to false (opt-in) either way.
				f := false
				pr.Apply = &f
				// A dangerous remediation also starts un-acknowledged: apply refuses to
				// converge it until this is flipped true (or --i-understand-danger is passed).
				if e.Danger != "" {
					ack := false
					pr.Acknowledged = &ack
				}
				pr.Remediation = e.Remediation
				if e.Remediation != nil && e.Remediation["resource"] == "choose" {
					def, _ := e.Remediation["default"].(string) // platform default, overridable
					pr.Choose = &def
				}
			case "not_applicable":
				if e.RequiresPackage != "" {
					baseline[e.RequiresPackage]++
					pr.ActivatedBy = e.RequiresPackage
				}
			}
			rules[c.ID] = pr
		}
	}

	pkgs := make([]baselinePkg, 0, len(baseline))
	for name, n := range baseline {
		pkgs = append(pkgs, baselinePkg{Name: name, Activates: n, Apply: false})
	}
	sort.Slice(pkgs, func(i, j int) bool { return pkgs[i].Name < pkgs[j].Name })

	plan := map[string]any{
		"target":            target,
		"os":                osName,
		"generated_from":    jsonPath,
		"summary":           counts,
		"baseline_packages": pkgs,
		"rules":             rules,
	}

	outPath := hdOut
	if outPath == "" {
		outPath = fmt.Sprintf("hardening-plan-%s.yml", osName)
	}
	body, err := yaml.Marshal(plan)
	if err != nil {
		return err
	}
	header := "# pavois hardening plan (state-aware). Flip `apply: true` on the gaps you want fixed.\n" +
		"# compliant rules are shown for context and are never applied.\n" +
		"# items with a `danger:` line can brick or lock out the host: read it, then set\n" +
		"# `acknowledged: true` to allow apply (or pass --i-understand-danger to apply).\n" +
		"# SSH access can be scoped from the plan: add `ssh_allow_from: [cidr, ...]` on\n" +
		"# firewall-default-deny to restrict SSH to those sources, and `ssh_allow_users:`/\n" +
		"# `ssh_allow_groups:` on misc-sshd-limit-user-access (must include the account you\n" +
		"# connect as, or you lock yourself out).\n"
	if err := os.WriteFile(outPath, append([]byte(header), body...), 0o600); err != nil {
		return err
	}
	_, _ = fmt.Fprintf(cmd.OutOrStdout(),
		"pavois: plan → %s  (compliant %d · gaps %d · n/a %d · baseline installs %d)\n",
		outPath, counts["compliant"], counts["gap"], counts["not_applicable"], len(pkgs))
	_ = transport
	return nil
}

// --- harden apply: compile the enabled plan into a native Chef recipe + converge ---

type planFile struct {
	Target           string `yaml:"target"`
	OS               string `yaml:"os"`
	BaselinePackages []struct {
		Name  string `yaml:"name"`
		Apply bool   `yaml:"apply"`
	} `yaml:"baseline_packages"`
	Rules map[string]struct {
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
	} `yaml:"rules"`
}

func s(v any) string {
	if v == nil { // an absent map key must be "", not the literal "<nil>" (broke conf_line's reload)
		return ""
	}
	return strings.TrimSpace(fmt.Sprintf("%v", v))
}

// confLine is an in-place `key = value` edit in a file Pavois does NOT own wholesale
// (e.g. /etc/audit/auditd.conf): replace the line if present, append if missing, vs the
// keyval resource which rewrites the whole drop-in file.
type confLine struct{ file, key, value, reload, sep string } // sep "space" for login.defs (KEY VALUE), else "key = value"

// pamLine inserts a full PAM stack line before an anchor pattern (so module order is correct,
// e.g. pam_pwhistory before pam_unix in the password stack), skipped if the module is already
// present. Used for /etc/pam.d/common-* where ordering matters and a blind append is wrong.
type pamLine struct{ file, module, before, line string }

// execRem is a guarded shell command for cases no declarative resource fits cleanly: e.g.
// chmod over a glob (/etc/ssh/*.pub, /boot/System.map-*). not_if keeps it idempotent.
type execRem struct{ name, command, notIf string }

// manualFix is a remediation Pavois DELIVERS as a reviewable script but NEVER runs itself:
// because the fix needs human judgement (deleting a rogue uid-0 account) or is operationally
// risky (removing compilers, noexec on /var, repartitioning, dropping sudo NOPASSWD). Same
// "deliver, don't execute" contract as the KSPP kernel-build recipe.
type manualFix struct{ id, command, reason string }

// mountAgg accumulates the desired tmpfs options for one mount point (e.g. /dev/shm gets
// nodev+nosuid+noexec from three separate controls) so the mount resource carries them all.
type mountAgg struct {
	device, fstype string
	bind           bool // self-bind a real dir (/home, /var) to carry options without a separate partition
	opts           map[string]bool
}

func sortedMountKeys(m map[string]*mountAgg) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		if k != "" {
			out = append(out, k)
		}
	}
	sort.Strings(out)
	return out
}

// compileRecipe turns the enabled plan items into idiomatic, idempotent, BATCHED
// Chef resources. No bash, ever: config files use the native `file` resource. It
// collects per target so contradictions (same key/path/service, different values)
// are caught as CONFLICTS before anything is applied.
// firstArg returns one argument from a kernel command line, used as the witness that grubby
// really applied them. Checking one is enough: grubby writes them as a set.
func firstArg(args string) string {
	for _, a := range strings.Fields(args) {
		if a != "" {
			return a
		}
	}
	return ""
}

func compileRecipe(p planFile, auditRules, kernelRecipe, grubPassword, std string) (string, int, bool, int, []string) {
	var b strings.Builder
	// Ruby reads a source file in the locale's encoding unless told otherwise, and a stock
	// debian13 runs sudo with LANG unset, so US-ASCII. Every non-ASCII byte in this recipe
	// (an accented rule title, a quoted message) would then be refused before a single
	// resource runs: "invalid multibyte character 0xE2", measured on a fresh debian13 VM.
	// The em-dashes that triggered it are gone from the tree, but a rule title can carry an
	// accent at any time, so the magic comment stays. It must be the FIRST line.
	b.WriteString("# encoding: utf-8\n")
	b.WriteString("# Generated by `pavois harden apply`: native Chef resources, no bash.\n")
	b.WriteString("# Idempotent and batched. Apply with cinc-apply.\n\n")
	reboot := false
	pendingEnabled := 0
	// ensureDir guarantees a drop-in's parent .d exists BEFORE its file is written. A missing
	// parent makes Chef's file resource abort the whole run (EnclosingDirectoryDoesNotExist), and
	// which .d dirs ship varies by OS (RHEL 8 has no /etc/ssh/sshd_config.d, no /etc/default/grub.d).
	// Deduped so it is emitted once per dir; recursive so nested paths are covered.
	dirsDone := map[string]bool{}
	ensureDir := func(dir string) {
		if dir == "" || dir == "/" || dir == "." || dirsDone[dir] {
			return
		}
		dirsDone[dir] = true
		_, _ = fmt.Fprintf(&b, "directory %q do\n  recursive true\nend\n\n", dir)
	}
	auditRuleset := false
	noexecUser := "" // set when sudo-noexec is applied -> exempt the mgmt user (below)
	var conflicts []string

	inst := map[string]bool{}
	rm := map[string]bool{}
	sysctl := map[string]string{} // key -> value
	sshd := map[string]string{}   // directive -> value
	sshdEnabled := false          // an sshd_setting (or AllowUsers) is ACTIVELY enabled: not just compliant siblings
	allowUsersSet := false        // the plan explicitly set ssh_allow_users/groups (else preserve the live value)
	svc := map[string]string{}    // service -> "action[…]"
	// Exclusive groups (firewall, syslog, time-sync) are resolved ACROSS the whole plan:
	// candidates = every technology the group offers, chosen = the ones a control picked.
	exclCandidates := map[string]bool{}
	exclChosen := map[string]bool{}
	files := map[string]map[string]string{}   // path -> attr -> value
	dirs := map[string]map[string]string{}    // directory path -> attr -> value (mode/owner/group)
	keyvals := map[string]map[string]string{} // config file -> key -> value (drop-in, whole-file)
	authselectFeatures := map[string]bool{}   // RHEL authselect features to enable (with-faillock, …)
	confLines := []confLine{}                 // in-place key=value edits in a shared file (auditd.conf)
	pamLines := []pamLine{}                   // PAM stack lines inserted before an anchor (idempotent)
	execs := []execRem{}                      // arbitrary guarded command (e.g. chmod on a glob)
	kmods := map[string]bool{}
	cmdline := map[string]bool{}     // kernel cmdline params -> one grub drop-in
	mounts := map[string]*mountAgg{} // mount point -> aggregated tmpfs options (all-or-nothing)
	fwEnableCmd := ""                // firewall: open SSH then enable (no lockout), emitted once
	fwNftConfig := ""                // native nftables ruleset (hardened-kernel friendly), emitted once
	grubPwWanted := false            // a grub_password remediation was enabled
	// WHAT to do to grub is policy and lives in the RULE (command_apt / command_rhel); the engine
	// only generates the secret, vaults it, and executes. harden.go is the engine (#157).
	grubCmdApt, grubCmdRhel := "", ""
	dconfEntries := map[string]string{} // dconf key -> value, aggregated from the rule data
	faillockWanted := false             // a pam_faillock remediation was enabled
	faillockParams := ""                // pam_faillock module args (from the rule data)
	kernelBuildWanted := false          // a kernel_build remediation was enabled (deliver the recipe)
	selinuxWanted := false              // a selinux_state remediation was enabled (RHEL enforcing)
	manualFixes := []manualFix{}        // `manual` remediations: delivered as a script, never auto-run

	setKV := func(m map[string]string, k, v, kind string) {
		if old, ok := m[k]; ok && old != v {
			conflicts = append(conflicts, fmt.Sprintf("%s %q: %q vs %q", kind, k, old, v))
		}
		m[k] = v
	}

	for _, bp := range p.BaselinePackages {
		if bp.Apply {
			inst[bp.Name] = true
		}
	}
	// Sorted, not map order: everything this loop appends to a list (conf lines, PAM edits,
	// execs) would otherwise come out shuffled on every run. The same plan must compile to the
	// same recipe: the restore point photographs what the recipe will touch, the evidence
	// bundle digests it, and PAM is a stack where order is correctness, not preference.
	for _, cid := range slices.Sorted(maps.Keys(p.Rules)) {
		r := p.Rules[cid]
		enabled := r.Apply != nil && *r.Apply
		res := ""
		if r.Remediation != nil {
			res = s(r.Remediation["resource"])
		}
		// Aggregated drop-ins (sysctl/sshd/cmdline/keyval/mount) are all-or-nothing: regenerating
		// one from only the enabled gaps would DROP compliant controls' settings and regress them
		// (e.g. wipe /etc/sysctl.d/zz-pavois.conf down to the one gap, re-enable root SSH). So also
		// pull in COMPLIANT aggregated controls: the drop-in then holds the complete desired
		// state. They contribute their setting only (no pkg/reboot side effects).
		aggregated := res == "sysctl" || res == "sshd_setting" || res == "kernel_cmdline" || res == "keyval" || res == "mount" || res == "dconf"
		keepCompliant := aggregated && !enabled && r.Status == "compliant"
		if !enabled && !keepCompliant {
			continue
		}
		if enabled { // side effects only for controls we are actively fixing
			// rule dependency: a prerequisite package must be present first (e.g. the audit
			// ruleset needs auditd, which owns /etc/audit/rules.d/): emitted before files.
			if r.RequiresPackage != "" {
				inst[r.RequiresPackage] = true
			}
			// `Defaults noexec` severs Pavois's own sudo→cinc path: self-exempt (below).
			if cid == "sudo-noexec" {
				if i := strings.Index(p.Target, "@"); i > 0 {
					noexecUser = p.Target[:i]
				}
			}
		}
		// misc-sshd-limit-user-access is manual by default (which users/groups may SSH is
		// site-specific, Pavois cannot guess it). If the operator listed them in the plan,
		// enforce AllowUsers/AllowGroups as an sshd drop-in instead of a manual script. This runs
		// BEFORE the nil-remediation skip below: the control carries a remediation only for some
		// OSes, but the operator's override must apply on EVERY OS (else SSH access-limiting is
		// silently dropped where no @os remediation exists: e.g. debian13, ubuntu, RHEL).
		// NB: the list MUST include the account Pavois connects as, or SSH locks out.
		if enabled && cid == "misc-sshd-limit-user-access" && (len(r.SSHAllowUsers) > 0 || len(r.SSHAllowGroups) > 0) {
			sshdEnabled = true
			allowUsersSet = true
			if len(r.SSHAllowUsers) > 0 {
				setKV(sshd, "allowusers", strings.Join(r.SSHAllowUsers, " "), "sshd")
			}
			if len(r.SSHAllowGroups) > 0 {
				setKV(sshd, "allowgroups", strings.Join(r.SSHAllowGroups, " "), "sshd")
			}
			continue
		}
		if r.Remediation == nil {
			if enabled {
				pendingEnabled++ // enabled but no remediation yet: don't skip silently
			}
			continue
		}
		m := r.Remediation
		// Remediation always applies the MOST-SECURE value (hardening = max); the per-norm
		// threshold is an AUDIT concern (--standard X checks X's requirement via the rule's check).
		_ = std
		if enabled {
			if rb, ok := m["reboot_required"].(bool); ok && rb {
				reboot = true
			}
		}
		switch res {
		case "choose":
			// "<group>-present" gap: the admin picked a technology to set up
			opts, _ := m["options"].(map[string]any)
			if o, ok := opts[r.Choose].(map[string]any); ok {
				inst[s(o["package"])] = true
				// An exclusive group means ONE technology, and the plan may contain SEVERAL controls
				// of the same group (firewall-present picks the daemon, firewall-default-deny picks
				// the policy). Never decide "what to disable" from one control alone: two controls
				// whose defaults differ would each disable the other's pick, and a hardened host
				// would come out with NO firewall at all (measured on a clean-room debian12: ufw and
				// nftables both installed, both dead). Record the candidates and the picks here, and
				// resolve the whole group ONCE, after every control has spoken.
				for name, v := range opts {
					vo, _ := v.(map[string]any)
					if vo == nil || s(vo["service"]) == "" {
						continue
					}
					exclCandidates[s(vo["service"])] = true
					if name == r.Choose {
						exclChosen[s(vo["service"])] = true
					}
				}
				// Firewall policy (the nftables ruleset, the ufw command sequence) lives in the
				// rule as DATA: see the `ruleset`/`enable_cmd` fields on the option. Here we only
				// substitute the dynamic SSH allow-list: `ssh_allow_from` in the plan restricts SSH
				// to those sources; empty = open to all (the safe default so a plan without it never
				// locks the admin out). A firewall stays up first so Pavois isn't cut off.
				var srcs []string
				for _, src := range r.SSHAllowFrom {
					if src = strings.TrimSpace(src); src != "" {
						srcs = append(srcs, src)
					}
				}
				if ruleset := s(o["ruleset"]); ruleset != "" {
					// nftables-style: a ruleset template with a %SSH_RULE% placeholder.
					sshRule := s(o["ssh_rule"])
					if len(srcs) > 0 && s(o["ssh_rule_from"]) != "" {
						sshRule = strings.ReplaceAll(s(o["ssh_rule_from"]), "%CIDRS%", strings.Join(srcs, ", "))
					}
					fwNftConfig = strings.ReplaceAll(ruleset, "%SSH_RULE%", sshRule)
				} else if enableCmd := s(o["enable_cmd"]); enableCmd != "" {
					// ufw-style: an enable command with a %SSH_ALLOW% placeholder.
					allow := s(o["ssh_allow"])
					if len(srcs) > 0 && s(o["ssh_allow_from"]) != "" {
						var parts []string
						for _, src := range srcs {
							parts = append(parts, strings.ReplaceAll(s(o["ssh_allow_from"]), "%SRC%", src))
						}
						allow = strings.Join(parts, "; ")
					}
					fwEnableCmd = strings.ReplaceAll(enableCmd, "%SSH_ALLOW%", allow)
				} else {
					setKV(svc, s(o["service"]), ":enable, :start", "service")
				}
			} else {
				conflicts = append(conflicts,
					fmt.Sprintf("%s: set `choose:` to one of %s", cid, strings.Join(sortedAnyKeys(opts), ", ")))
			}
		case "sshd_setting":
			setKV(sshd, s(m["directive"]), s(m["value"]), "sshd")
			if enabled {
				sshdEnabled = true
			}
		case "package":
			if s(m["action"]) == "remove" {
				rm[s(m["name"])] = true
			} else {
				inst[s(m["name"])] = true
			}
		case "sysctl":
			setKV(sysctl, s(m["key"]), s(m["value"]), "sysctl")
		case "service":
			acts := ":disable, :stop"
			if a, ok := m["action"].([]any); ok {
				parts := make([]string, len(a))
				for i, x := range a {
					parts[i] = ":" + s(x)
				}
				acts = strings.Join(parts, ", ")
			}
			setKV(svc, s(m["name"]), acts, "service")
		case "keyval":
			f := s(m["file"])
			if keyvals[f] == nil {
				keyvals[f] = map[string]string{}
			}
			setKV(keyvals[f], s(m["key"]), s(m["value"]), "keyval "+f)
		case "conf_line":
			confLines = append(confLines, confLine{
				file: s(m["file"]), key: s(m["key"]), value: s(m["value"]), reload: s(m["service"]), sep: s(m["sep"])})
		case "pam_line":
			pamLines = append(pamLines, pamLine{
				file: s(m["file"]), module: s(m["module"]), before: s(m["before"]), line: s(m["line"])})
		case "exec":
			execs = append(execs, execRem{name: s(m["name"]), command: s(m["command"]), notIf: s(m["not_if"])})
		case "manual":
			// not auto-run: collected into a single delivered script the admin reviews and runs.
			manualFixes = append(manualFixes, manualFix{id: cid, command: s(m["command"]), reason: s(m["reason"])})
		case "dconf":
			if k := s(m["key"]); k != "" { // GNOME dconf key=value, aggregated into the db below
				dconfEntries[k] = s(m["value"])
			}
		case "pam_faillock":
			faillockWanted = true // enable account lockout, emitted below
			if p := s(m["params"]); p != "" {
				faillockParams = p // module args (deny/unlock_time/…) come from the rule data
			}
		case "authselect":
			// RHEL PAM stack: authselect owns system-auth/password-auth and places the modules
			// (pam_faillock, pam_pwhistory). The per-option knobs live in /etc/security/*.conf
			// (handled by keyval): here we only collect the FEATURES to enable. no-ops on Debian.
			if fs, ok := m["features"].([]any); ok {
				for _, f := range fs {
					if fv := s(f); fv != "" {
						authselectFeatures[fv] = true
					}
				}
			}
		case "selinux_state":
			selinuxWanted = true // enforce SELinux (RHEL family), emitted below
		case "kernel_build":
			kernelBuildWanted = true // deliver (not run) the KSPP kernel-build recipe, below
		case "audit_ruleset":
			auditRuleset = true // deploy the Pavois audit ruleset once (below)
		case "kernel_module":
			kmods[s(m["name"])] = true
		case "kernel_cmdline":
			cmdline[s(m["param"])] = true // aggregated into one grub drop-in (below)
		case "mount":
			mp := s(m["mount_point"])
			ma := mounts[mp]
			if ma == nil {
				ma = &mountAgg{device: s(m["device"]), fstype: s(m["fstype"]), opts: map[string]bool{}}
				if b, _ := m["bind"].(bool); b { // self-bind: device is the dir itself, fstype none
					ma.bind, ma.device, ma.fstype = true, mp, "none"
				}
				mounts[mp] = ma
			}
			ma.opts[s(m["option"])] = true // options aggregated per mount point (below)
		case "grub_password":
			grubPwWanted = true // Pavois generates the secret + vaults it (below)
			grubCmdApt, grubCmdRhel = s(m["command_apt"]), s(m["command_rhel"])
		case "file":
			path := s(m["path"])
			if files[path] == nil {
				files[path] = map[string]string{}
			}
			if s(m["action"]) == "delete" { // ensure-absent: native `file ... action :delete`
				files[path]["action"] = "delete"
				break
			}
			for _, k := range []string{"owner", "group", "mode", "content", "verify"} {
				if v, ok := m[k]; ok {
					val := s(v)
					// A config file must end with a newline: the stricter visudo in Ubuntu 26.04
					// rejects a sudoers drop-in with no trailing line terminator ("missing line
					// terminator at end of file"), which aborts the whole converge. Harmless elsewhere.
					if k == "content" && val != "" && !strings.HasSuffix(val, "\n") {
						val += "\n"
					}
					setKV(files[path], path+"#"+k, val, "file "+k)
					files[path][k] = val
				}
			}
		case "directory":
			path := s(m["path"])
			if dirs[path] == nil {
				dirs[path] = map[string]string{}
			}
			for _, k := range []string{"owner", "group", "mode"} {
				if v, ok := m[k]; ok {
					dirs[path][k] = s(v)
				}
			}
		}
	}
	for name := range inst {
		if rm[name] {
			conflicts = append(conflicts, fmt.Sprintf("package %q: install vs remove", name))
		}
	}

	n := 0
	if noexecUser != "" {
		// Emit the self-exemption FIRST: keep `Defaults noexec` for everyone, but let the
		// management user exec under sudo so Pavois keeps running cinc. Must precede the
		// noexec drop-in so a mid-converge abort can never leave noexec WITHOUT the exemption
		// (which would sever Pavois). Per-user override wins; visudo-verified.
		// strings.Builder.Write never errors, so the Fprintf return is safely discarded.
		_, _ = fmt.Fprintf(&b, "file %q do\n  content %q\n  owner 'root'\n  group 'root'\n  mode '0440'\n  verify 'visudo -cf %%{path}'\nend\n\n",
			"/etc/sudoers.d/zz-pavois-mgmt-exec",
			"# pavois: the management user runs cinc (which execs programs), so it must be\n"+
				"# exempt from Defaults noexec. noexec still applies to every other user.\n"+
				"Defaults:"+noexecUser+" !noexec\n")
		n++
	}
	// Refresh the apt cache ONCE before any install: on a stale cache apt reports "no
	// installation candidate" and, with ignore_failure below, the package silently never
	// installs (the control then fails forever). only_if apt-get so RHEL/dnf is unaffected.
	if len(inst) > 0 {
		// self-guarded command (no Chef guard: the string guard interpreter can trip a
		// cinc-apply ChefPowerShell load bug); no-op on non-apt systems.
		_, _ = fmt.Fprintf(&b, "execute 'pavois-apt-update' do\n  command 'if command -v apt-get >/dev/null 2>&1; then apt-get update; fi'\n  ignore_failure true\nend\n\n")
		n++
	}
	// Install ALL packages in ONE transaction (was one resource per package): on dnf especially, a
	// per-package resource re-runs mirror selection + metadata refresh every time (~1 pkg / 20s ->
	// tens of minutes on a full apply). We keep the cross-OS robustness that the per-package loop
	// gave (cross-OS lists carry names absent here: RHEL httpd/bind, virtual telnet/ftp): dnf gets
	// `--setopt=strict=0` (install the available ones, skip the rest instead of aborting), and on
	// apt we filter through `apt-cache show` first (local, no mirror hit) so an unknown name can't
	// abort the batch. ignore_failure so a package-manager hiccup never tanks the converge.
	if names := sortedKeys(inst); len(names) > 0 {
		list := strings.Join(names, " ")
		// One transaction per package manager, each tolerant of names absent on this OS (cross-OS
		// lists leak RHEL httpd/bind, virtual telnet/ftp): dnf `--setopt=strict=0` and zypper
		// `--ignore-unknown` skip the missing ones; on apt we pre-filter through `apt-cache show`.
		// dnf/zypper/apt cover every pavois target and then some (Chef's generic package resource
		// handled zypper/yum too; keep that breadth). On RHEL/clones enable EPEL first (best-effort):
		// many hardening tools live only in EPEL, else those installs `no match`.
		cmd := "if command -v dnf >/dev/null 2>&1; then dnf install -y epel-release 2>/dev/null || true; dnf install -y --skip-broken --setopt=strict=0 " + list +
			"; elif command -v zypper >/dev/null 2>&1; then zypper --non-interactive install --no-recommends --ignore-unknown " + list +
			"; elif command -v apt-get >/dev/null 2>&1; then P=\"\"; for p in " + list +
			"; do apt-cache show \"$p\" >/dev/null 2>&1 && P=\"$P $p\"; done; [ -n \"$P\" ] && DEBIAN_FRONTEND=noninteractive apt-get install -y $P; fi; true"
		_, _ = fmt.Fprintf(&b, "execute 'pavois-install-packages' do\n  command %q\n  ignore_failure true\nend\n\n", cmd)
		n += len(names)
	}
	if k := sortedKeys(rm); len(k) > 0 {
		for _, name := range k {
			_, _ = fmt.Fprintf(&b, "package %q do\n  action :remove\n  ignore_failure true\nend\n\n", name)
		}
		n += len(k)
	}
	if fwEnableCmd != "" { // AFTER the package batch so ufw is installed; open SSH then enable
		// Guard on ufw's OWN active state, NOT `systemctl is-active ufw`: installing the ufw
		// package leaves the unit active-by-default while the firewall itself is disabled
		// (ENABLED=no, no ruleset), so a systemd guard skips `ufw enable` and we ship no rules.
		// ignore_failure: if ufw is missing or enable fails, that firewall control just stays
		// failing in the re-scan: it must NOT abort the whole converge and regress the host.
		_, _ = fmt.Fprintf(&b, "execute 'pavois-firewall-enable' do\n  command %q\n  ignore_failure true\n  not_if '/usr/sbin/ufw status 2>/dev/null | grep -q \"Status: active\"'\nend\n\n", fwEnableCmd)
		n++
	}
	// One firewall, one syslog, one time-sync: disable the candidates NOBODY picked. Doing this per
	// control would make two controls of the same group cancel each other out (that is exactly how a
	// hardened host ended up with ufw and nftables both installed and both dead).
	var unpicked []string
	for s2 := range exclCandidates {
		if !exclChosen[s2] {
			unpicked = append(unpicked, s2)
		}
	}
	if len(unpicked) > 0 {
		sort.Strings(unpicked)
		execs = append(execs, execRem{
			name: "pavois-exclusive-groups",
			command: "for s in " + strings.Join(unpicked, " ") +
				"; do systemctl list-unit-files ${s}.service --no-legend 2>/dev/null | grep -q . && " +
				"systemctl disable --now $s 2>/dev/null; done; true",
		})
		n++
	}

	if fwNftConfig != "" { // native nftables: write the ruleset, load it, enable the unit
		// ignore_failure on the load+service: a bad ruleset or missing package leaves the firewall
		// control failing (visible in the re-scan), never aborts the run.
		_, _ = fmt.Fprintf(&b, "file '/etc/nftables.conf' do\n  content %q\n  mode '0600'\nend\n\n", fwNftConfig)
		_, _ = fmt.Fprintf(&b, "execute 'pavois-nft-load' do\n  command 'nft -f /etc/nftables.conf'\n  ignore_failure true\n  subscribes :run, 'file[/etc/nftables.conf]', :immediately\nend\n\n")
		// RHEL's nftables.service does NOT read /etc/nftables.conf: it loads what
		// /etc/sysconfig/nftables.conf includes. Without this, the ruleset is live until the next
		// reboot and the box comes back with an EMPTY firewall (seen on rhel10: nftables active,
		// zero rules, and the default-deny control failing while the host was in fact wide open).
		bootInc := "if [ -f /etc/sysconfig/nftables.conf ] && ! grep -q '/etc/nftables.conf' " +
			"/etc/sysconfig/nftables.conf; then printf 'include \"/etc/nftables.conf\"\\n' >> " +
			"/etc/sysconfig/nftables.conf; fi; true"
		_, _ = fmt.Fprintf(&b, "execute 'pavois-nft-boot-include' do\n  command %q\n  ignore_failure true\nend\n\n", bootInc)
		_, _ = fmt.Fprintf(&b, "service 'nftables' do\n  action [:enable, :start]\n  ignore_failure true\nend\n\n")
		n++
	}
	if _, ok := sysctl["kernel.modules_disabled"]; ok {
		// kernel.modules_disabled=1 is a ONE-WAY switch: once set, no module can load until the
		// next reboot. In a sysctl.d drop-in it is applied by systemd-sysctl during sysinit,
		// BEFORE local-fs.target mounts /boot/efi (vfat) -> the vfat module can never load ->
		// "unknown filesystem type 'vfat'" -> local-fs fails -> emergency mode + a locked root =
		// an unrecoverable brick (proven via the offline journal on an EFI VM). Apply it LATE
		// instead: a oneshot ordered After=local-fs.target, so every boot-time module (vfat for
		// the EFI partition included) is loaded first, then module loading is locked. Still
		// reboot-survivable (the unit re-runs and re-locks on every boot).
		delete(sysctl, "kernel.modules_disabled")
		unitContent := "[Unit]\\n" +
			"Description=Pavois: lock kernel module loading (late, after boot modules are loaded)\\n" +
			"After=local-fs.target network-online.target\\n\\n" +
			"[Service]\\n" +
			"Type=oneshot\\n" +
			"RemainAfterExit=yes\\n" +
			"ExecStart=/sbin/sysctl -q -w kernel.modules_disabled=1\\n\\n" +
			"[Install]\\n" +
			"WantedBy=multi-user.target\\n"
		_, _ = fmt.Fprintf(&b, "file %q do\n  content \"%s\"\n  notifies :run, 'execute[pavois-modules-disabled-enable]', :immediately\nend\n\n",
			"/etc/systemd/system/pavois-modules-disabled.service", unitContent)
		b.WriteString("execute 'pavois-modules-disabled-enable' do\n  command 'systemctl daemon-reload && systemctl enable pavois-modules-disabled.service'\n  action :nothing\nend\n\n")
		n++
	}
	if len(sysctl) > 0 {
		// One high-priority drop-in (zz-Pavois sorts AFTER any 99-* system file, e.g.
		// /usr/lib/sysctl.d/99-protect-links.conf which would otherwise reset
		// fs.protected_fifos at boot) + a `sysctl --system` reload so the live value matches
		// what persists. The chef `sysctl` resource uses 99-chef-* and loses that race.
		var c strings.Builder
		for _, k := range sortedKeysS(sysctl) {
			c.WriteString(k + " = " + sysctl[k] + "\\n")
		}
		_, _ = fmt.Fprintf(&b, "file %q do\n  content \"%s\"\n  notifies :run, 'execute[pavois-sysctl-reload]', :immediately\nend\n\n",
			"/etc/sysctl.d/zz-pavois.conf", c.String())
		b.WriteString("execute 'pavois-sysctl-reload' do\n  command 'sysctl --system'\n  action :nothing\nend\n\n")
		n += len(sysctl)
		// Re-apply sysctls AFTER the network is up. systemd-sysctl runs at sysinit, before
		// networkd/cloud-init bring the interface up, and that late setup resets some
		// net.ipv4.conf.all/default keys (log_martians, rp_filter…) to the kernel default:
		// so the drop-in is correct but the live value is wrong after a reboot. A oneshot
		// ordered After=network-online.target reloads them once the interface exists.
		unit := "[Unit]\\nDescription=Pavois re-apply sysctl after network is online\\n" +
			"After=network-online.target\\nWants=network-online.target\\n" +
			"[Service]\\nType=oneshot\\nRemainAfterExit=yes\\nExecStart=/sbin/sysctl --system\\n" +
			"[Install]\\nWantedBy=multi-user.target\\n"
		_, _ = fmt.Fprintf(&b, "file %q do\n  content \"%s\"\n  notifies :run, 'execute[pavois-sysctl-reapply-enable]', :immediately\nend\n\n",
			"/etc/systemd/system/pavois-sysctl-reapply.service", unit)
		b.WriteString("execute 'pavois-sysctl-reapply-enable' do\n  command 'systemctl daemon-reload && systemctl enable pavois-sysctl-reapply.service'\n  action :nothing\nend\n\n")
		n++
	}
	for _, k := range sortedKeysS(svc) {
		// Guard: only act if the unit exists. A service for a package that isn't installed
		// (e.g. a mutually-exclusive alternative like syslogng when rsyslog is chosen)
		// must be SKIPPED, not abort the whole run. Packages install earlier in the recipe,
		// so a service we DO want is present by the time this runs.
		// Translate the desired actions into plain `systemctl` calls in ONE execute instead of Chef's
		// `service` resource: the Chef provider trips on RHEL units like auditd (RefuseManualStop /
		// static), erroring inside load_current_resource where even ignore_failure can't catch it.
		// only_if the unit exists; each verb is tolerant (|| true) so a refused stop/enable-of-static
		// never aborts the run. systemctl enable/start/disable/stop == the Chef actions on Debian.
		// The rule may name the unit with or without the suffix: normalise, or the guard below
		// looked for `rsync.service.service`, never matched, and the whole execute was SKIPPED:
		// which is how an ENABLED rsync daemon survived every apply on the debian golden.
		unit := k
		if !strings.Contains(unit, ".") {
			unit += ".service"
		}
		base := strings.TrimSuffix(unit, ".service")
		var svcCmds []string
		for _, a := range strings.Split(svc[k], ",") {
			verb := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(a), ":"))
			if verb != "" {
				svcCmds = append(svcCmds, "systemctl "+verb+" "+unit+" 2>/dev/null || true")
			}
		}
		// A SysV service (Debian rsync) has NO unit file at all: `systemctl cat` and
		// `list-unit-files` both fail on it, while systemctl still enables/disables it through
		// systemd-sysv-install. So the init script counts as the unit existing.
		guard := fmt.Sprintf("systemctl cat %s >/dev/null 2>&1 || test -e /etc/init.d/%s", unit, base)
		_, _ = fmt.Fprintf(&b, "execute 'pavois-service-%s' do\n  command %q\n  only_if %q\n  ignore_failure true\nend\n\n",
			base, strings.Join(svcCmds, "; "), guard)
		n++
	}
	for _, mod := range sortedKeys(kmods) {
		_, _ = fmt.Fprintf(&b, "file %q do\n  content \"install %s /bin/true\\nblacklist %s\\n\"\nend\n\n",
			"/etc/modprobe.d/pavois-"+mod+".conf", mod, mod)
		n++
	}
	// Ownership remediations reference service users (e.g. syslog) that may be absent:
	// chown then fails the whole run. Create each non-root owner as a system user FIRST
	// (idempotent: no-op if it already exists), so the desired ownership is achievable.
	owners := map[string]bool{}
	for _, fa := range files {
		if o, ok := fa["owner"]; ok && o != "" && o != "root" {
			owners[o] = true
		}
	}
	for _, o := range sortedKeys(owners) {
		_, _ = fmt.Fprintf(&b, "user %q do\n  system true\n  action :create\nend\n\n", o)
	}
	// A content file may live in a drop-in dir that doesn't exist yet (e.g.
	// /etc/systemd/journald.conf.d): create parents first or the file resource aborts the run.
	fileDirs := map[string]bool{}
	for path, fa := range files {
		if _, hasContent := fa["content"]; hasContent {
			fileDirs[filepath.Dir(path)] = true
		}
	}
	for _, d := range sortedKeys(fileDirs) {
		_, _ = fmt.Fprintf(&b, "directory %q do\n  recursive true\nend\n\n", d)
	}
	for _, path := range sortedFileKeys(dirs) {
		da := dirs[path]
		_, _ = fmt.Fprintf(&b, "directory %q do\n", path)
		for _, k := range []string{"owner", "group", "mode"} {
			if v, ok := da[k]; ok {
				_, _ = fmt.Fprintf(&b, "  %s %q\n", k, v)
			}
		}
		_, _ = fmt.Fprintf(&b, "  only_if { ::File.directory?(%q) }\nend\n\n", path)
		n++
	}
	for _, path := range sortedFileKeys(files) {
		fa := files[path]
		if fa["action"] == "delete" { // ensure-absent (idempotent, no-op if already gone)
			_, _ = fmt.Fprintf(&b, "file %q do\n  action :delete\nend\n\n", path)
			n++
			continue
		}
		_, hasContent := fa["content"]
		_, _ = fmt.Fprintf(&b, "file %q do\n", path)
		for _, k := range []string{"content", "owner", "group", "mode"} {
			if v, ok := fa[k]; ok {
				_, _ = fmt.Fprintf(&b, "  %s %q\n", k, v)
			}
		}
		if v, ok := fa["verify"]; ok { // e.g. visudo -cf %{path}: never ship an invalid file
			_, _ = fmt.Fprintf(&b, "  verify '%s'\n", v)
			// The verify still PROTECTS (invalid content is never written), but one rejected file
			// must not abort the WHOLE converge: e.g. Ubuntu 26.04 ships sudo-rs, which rejects
			// `Defaults logfile=…` ("unknown setting"), and without this that single control tanked
			// every other one. Failure is logged; that control just stays a gap for its own scan.
			b.WriteString("  ignore_failure true\n")
		}
		if !hasContent { // pure owner/perm fix: the `file` resource fails on a DIRECTORY or a
			// missing path (cross-OS noise like /var/log/apt). Guard so it SKIPS instead of
			// aborting the whole run; a real file gets fixed, anything else is left alone.
			_, _ = fmt.Fprintf(&b, "  only_if { ::File.file?(%q) }\n", path)
		}
		b.WriteString("end\n\n")
		if !hasContent { // the path may be a DIRECTORY (e.g. /var/log/apt): the file resource
			// above skipped it, so set owner/group/mode via a `directory` resource when it is one.
			_, _ = fmt.Fprintf(&b, "directory %q do\n", path)
			for _, k := range []string{"owner", "group", "mode"} {
				if v, ok := fa[k]; ok {
					_, _ = fmt.Fprintf(&b, "  %s %q\n", k, v)
				}
			}
			_, _ = fmt.Fprintf(&b, "  only_if { ::File.directory?(%q) }\nend\n\n", path)
		}
		n++
	}
	if owners["syslog"] { // log-ownership persistence: tell rsyslog to CREATE/reopen logs as
		// syslog:adm so the ownership the file resources just set survives a log rotation
		// (rsyslog-as-root otherwise recreates them root-owned). We deliberately do NOT drop
		// rsyslog's privileges: the deprecated $PrivDropToUser/$PrivDropToGroup directives make
		// rsyslog 8.2504 (Debian 13/Trixie) fail to start, and NO control checks the daemon's
		// runtime uid: they check file ownership, which $FileOwner/$FileGroup already satisfy.
		// The old privdrop drop-in is removed so it can't keep bricking rsyslog on re-apply.
		b.WriteString("file '/etc/rsyslog.d/00-pavois-privdrop.conf' do\n  action :delete\n" +
			"  notifies :restart, 'service[rsyslog]', :delayed\n" +
			"  only_if { ::File.exist?('/etc/rsyslog.d/00-pavois-privdrop.conf') }\nend\n\n")
		b.WriteString("file \"/etc/rsyslog.d/00-pavois-log-ownership.conf\" do\n" +
			"  content \"# pavois: own logs as syslog:adm (no privilege drop: breaks rsyslog on Trixie)\\n" +
			"\\$FileOwner syslog\\n\\$FileGroup adm\\n\\$FileCreateMode 0640\\n\"\n" +
			"  notifies :restart, 'service[rsyslog]', :delayed\n" +
			"  only_if { ::File.exist?('/etc/rsyslog.conf') }\nend\n\n")
		// Also chown the EXISTING logs (not just newly-created ones) so the current files match.
		// The not_if keeps it idempotent (only runs while a log is still root-owned) and it
		// restarts rsyslog so it reopens them.
		b.WriteString("execute 'pavois-chown-rsyslog-logs' do\n" +
			"  command 'for f in /var/log/syslog /var/log/messages /var/log/*.log; do [ -f \"$f\" ] && chown syslog:adm \"$f\"; done; true'\n" +
			"  not_if 'test \"$(stat -c %U /var/log/syslog 2>/dev/null)\" = syslog'\n" +
			"  notifies :restart, 'service[rsyslog]', :delayed\n" +
			"  only_if { ::File.exist?('/etc/rsyslog.conf') }\nend\n\n")
		// ignore_failure: a logging-daemon restart hiccup must NEVER abort the whole converge and
		// leave the box half-hardened (Chef stops on the first unhandled error otherwise).
		b.WriteString("service 'rsyslog' do\n  action :nothing\n  ignore_failure true\nend\n\n")
		n++
	}
	// RHEL PAM stack (authselect). Configuring /etc/security/faillock.conf or pwhistory.conf is
	// INERT unless the matching module is in system-auth/password-auth: and on RHEL those files
	// are owned by authselect (editing them by hand is regenerated away). So when a faillock/
	// pwhistory .conf is being written, infer the feature that places the module. Explicit
	// `authselect` remediations (e.g. use_authtok, which authselect puts inline, not in a .conf)
	// add their features too. One `authselect select` runs the lot; gated on `command -v
	// authselect`, so the whole block no-ops on Debian/Ubuntu (which use inline common-* edits).
	if _, ok := keyvals["/etc/security/faillock.conf"]; ok {
		authselectFeatures["with-faillock"] = true
	}
	if _, ok := keyvals["/etc/security/pwhistory.conf"]; ok {
		authselectFeatures["with-pwhistory"] = true
	}
	if len(authselectFeatures) > 0 {
		feats := sortedKeys(authselectFeatures)
		var guards []string
		for _, f := range feats {
			guards = append(guards, "authselect current 2>/dev/null | grep -q "+f)
		}
		_, _ = fmt.Fprintf(&b, "execute 'pavois-authselect' do\n  command 'authselect select sssd %s --force'\n  only_if 'command -v authselect >/dev/null 2>&1'\n  not_if %q\nend\n\n",
			strings.Join(feats, " "), strings.Join(guards, " && "))
		n++
	}
	// key=value drop-ins (pwquality, faillock): one file per config, all keys merged.
	// Their parent .d dir may not exist (e.g. /etc/security/faillock.conf.d) and `file`
	// won't create parents: emit a recursive `directory` first, deduped.
	kvDirs := map[string]bool{}
	for _, f := range sortedFileKeys(keyvals) {
		kvDirs[filepath.Dir(f)] = true
	}
	for _, d := range sortedKeys(kvDirs) {
		_, _ = fmt.Fprintf(&b, "directory %q do\n  recursive true\nend\n\n", d)
	}
	for _, f := range sortedFileKeys(keyvals) {
		var content strings.Builder
		for _, k := range sortedKeysS(keyvals[f]) {
			// Bare boolean directives (faillock/pwhistory: audit, even_deny_root, enforce_for_root)
			// carry no value: emit just the key, not `key = ` which the pam parsers reject.
			if v := keyvals[f][k]; v == "" {
				content.WriteString(k + "\\n")
			} else {
				content.WriteString(k + " = " + v + "\\n")
			}
		}
		_, _ = fmt.Fprintf(&b, "file %q do\n  content \"%s\"\nend\n\n", f, content.String())
		n++
	}

	// In-place `key = value` edits (auditd.conf): replace the line, append if absent. The not_if
	// makes it idempotent so the best-effort reload only fires on a real change (auditd refuses a
	// systemctl restart but accepts reload; `|| true` keeps the converge green if it can't reload).
	confSeen := map[string]bool{} // dedupe: several controls set the same key (e.g. PASS_MIN_LEN)
	for _, cl := range confLines {
		if confSeen[cl.file+cl.key] {
			continue
		}
		confSeen[cl.file+cl.key] = true
		// Separator differs by file: auditd.conf uses `key = value`, login.defs uses `KEY VALUE`.
		sepWrite, sepSed, sepExists, sepNot := " = ", "[[:space:]]*=", "[[:space:]]*=", "[[:space:]]*=[[:space:]]*" //nolint:gosec // G101 false positive: key/value separators (regex fragments), not credentials
		if cl.sep == "space" {
			sepWrite, sepSed, sepExists, sepNot = " ", "[[:space:]]", "[[:space:]]", "[[:space:]]+" //nolint:gosec // G101 false positive: whitespace separators for KEY VALUE config files, not credentials
		}
		line := cl.key + sepWrite + cl.value
		reload := ""
		if cl.reload != "" {
			reload = fmt.Sprintf("; systemctl reload %s 2>/dev/null || true", cl.reload)
		}
		_, _ = fmt.Fprintf(&b, "execute 'pavois-conf-%s' do\n  command 'sed -ri \"s|^[[:space:]]*%s%s.*|%s|\" %s; grep -qiE \"^[[:space:]]*%s%s\" %s || echo \"%s\" >> %s%s'\n  not_if 'grep -qiE \"^[[:space:]]*%s%s%s\\b\" %s'\nend\n\n",
			cl.key, cl.key, sepSed, line, cl.file, cl.key, sepExists, cl.file, line, cl.file, reload, cl.key, sepNot, cl.value, cl.file)
		n++
	}

	// PAM stack lines: insert before the anchor (preserving module order), idempotent on the
	// module's presence. A malformed line here can break auth, so we only touch a file that
	// already exists and never reorder existing lines: we add ours ahead of `before`.
	pamSeen := map[string]bool{} // dedupe: several controls share one module line
	for _, pl := range pamLines {
		if pamSeen[pl.file+pl.module] {
			continue
		}
		pamSeen[pl.file+pl.module] = true
		apply := fmt.Sprintf(`echo %q >> %s`, pl.line, pl.file) // no anchor -> append (e.g. umask in bashrc)
		if pl.before != "" {
			apply = fmt.Sprintf(`sed -ri "/%s/i %s" %s`, pl.before, pl.line, pl.file) // insert before anchor (PAM order)
		}
		name := strings.Map(func(r rune) rune {
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
				return r
			}
			return '-'
		}, pl.module)
		_, _ = fmt.Fprintf(&b, "execute 'pavois-pam-%s' do\n  command '%s'\n  only_if 'test -f %s'\n  not_if 'grep -qE \"%s\" %s'\nend\n\n",
			name, apply, pl.file, pl.module, pl.file)
		n++
	}

	execSeen := map[string]bool{} // several controls can share one command (e.g. chown journal)
	for _, ex := range execs {
		if execSeen[ex.name] {
			continue
		}
		execSeen[ex.name] = true
		_, _ = fmt.Fprintf(&b, "execute 'pavois-exec-%s' do\n  command %q\n", ex.name, ex.command)
		if ex.notIf != "" {
			_, _ = fmt.Fprintf(&b, "  not_if %q\n", ex.notIf)
		}
		b.WriteString("end\n\n")
		n++
	}

	// All sshd settings -> ONE drop-in, validated (sshd -t) before it goes live
	// (no lockout) and reloaded (not restarted, keeps existing sessions). Only rewrite it when an
	// sshd_setting is ACTIVELY enabled: `sshd` also collects COMPLIANT siblings (keepCompliant) so
	// the regenerated drop-in stays complete, but if nothing sshd is being changed we must NOT
	// touch the file: else an unrelated apply (packages, sysctl, audit) would regenerate it and
	// silently drop AllowUsers/AllowGroups (which come from a `manual` control, not re-emitted).
	if len(sshd) > 0 && sshdEnabled {
		var content strings.Builder
		for _, k := range sortedKeysS(sshd) {
			content.WriteString(k + " " + sshd[k] + "\\n")
		}
		// The drop-in dir is absent on RHEL 8 (only RHEL 9 / Debian ship it) and RHEL 8's
		// sshd_config has no Include line: so create the dir, then prepend
		// `Include /etc/ssh/sshd_config.d/*.conf` at the TOP of sshd_config. sshd takes the FIRST
		// value per keyword and reads drop-ins in lexical order, so the Pavois drop-in must sort
		// BEFORE the vendor ones to win: el9 ships 50-redhat.conf (X11Forwarding yes,
		// GSSAPIAuthentication yes) and Ubuntu ships 50-cloud-init.conf: a 99- name loses to them.
		// Hence 00-pavois.conf (loads first, Pavois wins). Delete a stale 99-pavois.conf from an
		// older apply so the two do not coexist. All idempotent.
		b.WriteString("directory '/etc/ssh/sshd_config.d' do\n  recursive true\n  mode '0700'\nend\n\n")
		b.WriteString("file '/etc/ssh/sshd_config.d/99-pavois.conf' do\n  action :delete\nend\n\n")
		// AllowUsers/AllowGroups is set by a `manual` control (site-specific): it is NOT in the
		// regenerated content unless the operator passed ssh_allow_users/groups in THIS plan. So
		// when they did not, PRESERVE whatever is effective now: capture before the overwrite,
		// re-append after: so rewriting the drop-in for some other sshd setting never widens SSH
		// back to "all users" (the recurring AllowUsers-drop regression).
		if !allowUsersSet {
			b.WriteString("execute 'pavois-sshd-capture-allow' do\n" +
				"  command %q{sshd -T 2>/dev/null | grep -iE '^(allowusers|allowgroups) ' > /run/pavois-sshd-allow || true}\nend\n\n")
		}
		_, _ = fmt.Fprintf(&b, "file %q do\n  content \"%s\"\n  verify 'sshd -t -f %%{path}'\n  notifies :run, 'execute[pavois-sshd-reload]', :delayed\nend\n\n",
			"/etc/ssh/sshd_config.d/00-pavois.conf", content.String())
		if !allowUsersSet {
			b.WriteString("execute 'pavois-sshd-restore-allow' do\n" +
				"  command %q{[ -s /run/pavois-sshd-allow ] && ! grep -qiE '^(allowusers|allowgroups) ' /etc/ssh/sshd_config.d/00-pavois.conf && cat /run/pavois-sshd-allow >> /etc/ssh/sshd_config.d/00-pavois.conf; rm -f /run/pavois-sshd-allow; true}\n" +
				"  notifies :run, 'execute[pavois-sshd-reload]', :delayed\nend\n\n")
		}
		b.WriteString("execute 'pavois-sshd-include' do\n" +
			"  command %q{sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config}\n" +
			"  not_if %q{grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d' /etc/ssh/sshd_config}\n" +
			"  notifies :run, 'execute[pavois-sshd-reload]', :delayed\nend\n\n")
		// Reload whichever unit exists (sshd on RHEL, ssh on Debian); non-fatal so a reload hiccup
		// never aborts the converge.
		b.WriteString("execute 'pavois-sshd-reload' do\n  command 'systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true'\n  action :nothing\nend\n\n")
		n += len(sshd)
	}
	if auditRuleset && auditRules != "" { // Pavois audit ruleset -> one file
		// mode 0640: audit rules must not be group/other-readable (fileperm-etc-audit-rulesd
		// checks `find -perm /0137`); a default 0644 file is world-readable and fails it.
		ensureDir("/etc/audit/rules.d") // present once auditd is installed; ensure it regardless
		_, _ = fmt.Fprintf(&b, "file %q do\n  content %q\n  mode '0640'\nend\n\n",
			"/etc/audit/rules.d/99-pavois.rules", auditRules)
		// Make sure auditd is up before loading: augenrules loads into the kernel AND recompiles
		// /etc/audit/audit.rules (what auditd reads at the next boot). Do this with a plain execute,
		// NOT Chef's `service` resource: RHEL's auditd unit (RefuseManualStop=yes) trips the service
		// provider. NEVER systemctl-restart auditd; enable + start (best-effort) is enough.
		b.WriteString("execute 'pavois-auditd-up' do\n" +
			"  command 'systemctl enable auditd 2>/dev/null; systemctl start auditd 2>/dev/null || service auditd start 2>/dev/null || true'\n" +
			"  ignore_failure true\nend\n\n")
		// Deploying the file is not enough: the rules only auto-load at the NEXT boot, so load now
		// with augenrules. Guard on whether OUR rule set is already RESIDENT (>=40 of the ~54 rules),
		// NOT on immutable state: the old `enabled 2` guard skipped the load once the config was
		// immutable, so the compiled /etc/audit/audit.rules was never refreshed and auditd loaded a
		// stale 1-rule file at boot. augenrules --load recompiles the file first, so even if the live
		// load is refused under `-e 2`, the full set loads on the next reboot. ignore_failure keeps a
		// refused load from aborting the converge. Full paths: augenrules/auditctl live in /sbin.
		b.WriteString("execute 'pavois-audit-load' do\n" +
			"  command '/sbin/augenrules --load 2>/dev/null || augenrules --load 2>/dev/null || true'\n" +
			"  not_if 'test \"$(auditctl -l 2>/dev/null | wc -l)\" -ge 40'\n  ignore_failure true\nend\n\n")
		// syscall auditing is INERT without audit=1 on the kernel cmdline (revealed by the
		// behavioral probe): fold it into the cmdline drop-in emitted below.
		cmdline["audit=1"] = true
		cmdline["audit_backlog_limit=8192"] = true
		n++
	}
	// All kernel cmdline params (audit + the R8 mitigations: spectre_v2, l1tf, mds…) go into
	// ONE grub drop-in that APPENDS to GRUB_CMDLINE_LINUX, then regenerate grub.cfg (no native
	// grub resource -> execute). Reboot needed to take effect.
	if len(cmdline) > 0 {
		// iommu=force forces the IOMMU and BRICKS virtualized guests (virtio disk/net vanish at
		// boot, the VM never returns). Apply it ONLY on bare metal: a guarded append skipped when
		// systemd-detect-virt sees a VM. Every other param is safe on both metal and guests.
		cmdKeys := sortedKeys(cmdline)
		safe := make([]string, 0, len(cmdKeys))
		iommuForce := false
		for _, k := range cmdKeys {
			if k == "iommu=force" {
				iommuForce = true
				continue
			}
			safe = append(safe, k)
		}
		args := strings.Join(safe, " ")
		// Debian's /etc/default/grub does NOT source /etc/default/grub.d/ (Ubuntu convention, varies
		// by image): guarantee the sourcing, or the drop-in never reaches grub.cfg. RHEL has no
		// grub.d at all; ensureDir keeps the file write from aborting there (grubby applies the args
		// directly regardless).
		ensureDir("/etc/default/grub.d")
		b.WriteString("execute 'pavois-grub-source-dropins' do\n" +
			`  command 'printf "\nif [ -d /etc/default/grub.d ]; then for x in /etc/default/grub.d/*.cfg; do [ -e \"\$x\" ] && . \"\$x\"; done; fi\n" >> /etc/default/grub'` +
			"\n  not_if 'grep -q /etc/default/grub.d /etc/default/grub'\nend\n\n")
		content := "GRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE_LINUX " + args + "\"\n"
		if iommuForce {
			content += "systemd-detect-virt -q -v || GRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE_LINUX iommu=force\"\n"
		}
		_, _ = fmt.Fprintf(&b, "file %q do\n  content %q\n  notifies :run, 'execute[pavois-grub-apply]', :immediately\nend\n\n",
			"/etc/default/grub.d/99-pavois-cmdline.cfg", content)
		// Regenerate the bootloader config the OS-native way: update-grub on Debian; grubby (BLS,
		// updates every kernel entry directly) on RHEL/clones; grub2-mkconfig as a last resort.
		// `update-grub` does not exist on RHEL, grubby does not on Debian: hence the detection.
		// grubby applies the arguments and MAY still exit non-zero, because on EL it finishes by
		// calling grub2-mkconfig against the EFI wrapper, which refuses the write. Judging the
		// converge on that exit code aborts a run whose work is already done, so the result is
		// checked instead: the arguments must be present in the entries afterwards.
		apply := "if command -v update-grub >/dev/null 2>&1; then update-grub; " +
			"elif command -v grubby >/dev/null 2>&1; then " +
			"grubby --update-kernel=ALL --args=\"" + args + "\" >/dev/null 2>&1 || true; " +
			"cfg=/boot/grub2/grub.cfg; [ -f \"$cfg\" ] && grub2-mkconfig -o \"$cfg\" >/dev/null 2>&1 || true; " +
			"grubby --info=ALL | grep -q -- \"" + firstArg(args) + "\" || " +
			"{ echo \"pavois: grubby did not apply the kernel arguments\" >&2; exit 1; }; "
		if iommuForce {
			apply += "systemd-detect-virt -q -v || grubby --update-kernel=ALL --args=\"iommu=force\"; "
		}
		// /boot/grub2/grub.cfg FIRST, not whatever `find` returns. On a Fedora EFI install the
		// first hit is /boot/efi/EFI/<distro>/grub.cfg, which is a wrapper: grub2-mkconfig
		// refuses to overwrite it ("will overwrite the GRUB wrapper... GRUB configuration file
		// was not updated"), exits 1, and takes the whole converge down with it. Measured on a
		// fresh fedora VM.
		apply += "elif command -v grub2-mkconfig >/dev/null 2>&1; then " +
			"cfg=/boot/grub2/grub.cfg; " +
			"[ -f \"$cfg\" ] || cfg=\"$(find /boot -name grub.cfg 2>/dev/null | head -1)\"; " +
			"grub2-mkconfig -o \"$cfg\"; fi"
		_, _ = fmt.Fprintf(&b, "execute 'pavois-grub-apply' do\n  command %q\n  action :nothing\nend\n\n", apply)
		reboot = true
		n++
	}
	// One mount resource per mount point, carrying the COMPLETE set of tmpfs options (nodev/
	// nosuid/noexec) so a subset apply never drops a compliant option. :enable persists it in
	// fstab; :remount applies it now if already mounted, :mount if not.
	for _, mp := range sortedMountKeys(mounts) {
		ma := mounts[mp]
		csv := strings.Join(sortedKeys(ma.opts), ",")
		ssv := strings.Join(sortedKeys(ma.opts), " ")
		if ma.bind {
			// This path is NOT a separate filesystem and there is no spare disk to make one. Auto
			// self-binding it into fstab to carry nodev/nosuid/noexec is fragile (a self-bind can
			// hang local-fs.target at boot, and it is not real persistence). Proper separation is a
			// deliberate, offline operation: DELIVER it as a manual fix, never auto-apply it.
			manualFixes = append(manualFixes, manualFix{
				id:     "mount " + mp,
				reason: mp + " is not a separate filesystem; carrying " + csv + " properly needs repartitioning (no spare disk to auto-create), and an auto self-bind can hang boot",
				command: fmt.Sprintf("# Harden %s with mount options: %s\n"+
					"# Recommended: give %s its OWN filesystem/partition, then set its /etc/fstab options to include %s.\n"+
					"# Interim ONLY (review, and verify boot in a SECOND session first): a bind mount with nofail:\n"+
					"#   echo '%s %s none bind,%s,nofail 0 0' >> /etc/fstab && mount %s\n",
					mp, csv, mp, csv, mp, mp, csv, mp),
			})
			n++
			continue
		}
		// :enable writes the fstab entry (persist). The live apply is an execute, NOT the :remount
		// action: Chef's :remount umounts first and that fails on a busy fs like /dev/shm. `mount -o
		// remount` rewrites options in place; if the point isn't a separate mount yet (e.g. /tmp on /),
		// `mount <mp>` mounts it from the fstab line we just wrote. Guarded idempotent on the options.
		// pass 0 + dump 0: a tmpfs has NO device to fsck. Chef's mount resource defaults pass to 2,
		// which makes systemd fsck the tmpfs at boot, fail, and drop to emergency mode (root locked
		// = unrecoverable). Force pass 0. nofail is the extra belt: a failed mount never hangs boot.
		_, _ = fmt.Fprintf(&b, "mount %q do\n  device %q\n  fstype %q\n  options %q\n  pass 0\n  dump 0\n  action :enable\nend\n\n",
			mp, ma.device, ma.fstype, csv+",nofail")
		_, _ = fmt.Fprintf(&b, "execute 'pavois-mount-%s' do\n  command 'mountpoint -q %s && mount -o remount,%s %s || mount %s'\n  not_if 'O=$(findmnt -no OPTIONS %s 2>/dev/null); for o in %s; do echo \"$O\" | grep -qw \"$o\" || exit 1; done'\nend\n\n",
			mp, mp, csv, mp, mp, mp, ssv)
		n++
	}
	if grubPwWanted && grubPassword != "" {
		// Pavois generated the password and vaulted it locally; here we hash it ON the target
		// (grub-mkpasswd-pbkdf2 is salted) and write the superuser entry. The plaintext lands in
		// a 0600 temp file, used then removed. Idempotent: skip if a grub password already exists.
		_, _ = fmt.Fprintf(&b, "file '/tmp/pavois-grub-pw' do\n  content %q\n  mode '0600'\nend\n\n", grubPassword)
		// Debian-only grub.d SCRIPT (update-grub emits its directives into grub.cfg, reading the
		// salted hash from a sibling dotfile). only_if update-grub so it is NOT written on RHEL,
		// which reads /boot/grub2/user.cfg directly (grub2 password path below).
		_, _ = fmt.Fprintf(&b, "file '/etc/grub.d/40_pavois_password' do\n  content %q\n  mode '0755'\n  only_if { ::File.exist?('/usr/sbin/update-grub') || ::File.exist?('/usr/bin/update-grub') }\nend\n\n",
			"#!/bin/sh\ncat <<EOF\nset superusers=\"root\"\npassword_pbkdf2 root $(cat /etc/grub.d/.pavois-grub-hash)\nEOF\n")
		// Hash the plaintext ON the target (pbkdf2 is salted), then persist the OS-native way:
		//  - Debian: hash dotfile + `--unrestricted` on 10_linux (a superuser WITHOUT --unrestricted
		//    blocks every boot) + update-grub.
		//  - RHEL/clones: write GRUB2_PASSWORD to /boot/grub2/user.cfg (grub sources it, superuser
		//    root is implicit, and booting the default entry stays password-free: no brick).
		// ignore_failure: a grub-password hiccup must never abort the converge (it is a danger item).
		// The engine's job here is the SECRET (generate it, vault it, hand it to the target) and the
		// execution. WHAT to do to grub is policy, and policy lives in the rule (docs/reference/
		// rules.yml, grub-password: `command_apt` / `command_rhel`), like audit.rules and the kernel
		// recipe. harden.go is the engine, the rules are the content (#157).
		pwfile := "/tmp/pavois-grub-pw" //nolint:gosec // a path, not a credential
		deb, rhel := grubCmdApt, grubCmdRhel
		if deb == "" || rhel == "" {
			conflicts = append(conflicts,
				"grub-password: the rule must carry command_apt and command_rhel (the policy is data)")
		}
		deb = strings.ReplaceAll(deb, "%{pwfile}", pwfile)
		rhel = strings.ReplaceAll(rhel, "%{pwfile}", pwfile)
		if deb == "" || rhel == "" {
			deb, rhel = "true", "true" // the conflict above already refuses the run
		}
		cmd := "if command -v update-grub >/dev/null 2>&1; then " + deb +
			"; elif command -v grub2-mkpasswd-pbkdf2 >/dev/null 2>&1; then " + rhel +
			"; fi; rm -f " + pwfile
		_, _ = fmt.Fprintf(&b, "execute 'pavois-grub-password' do\n  command %q\n"+
			"  not_if 'test -s /etc/grub.d/.pavois-grub-hash || test -s /boot/grub2/user.cfg'\n"+
			"  ignore_failure true\nend\n\n", cmd)
		reboot = true
		n++
	}
	if faillockWanted {
		// pam_faillock via DIRECT common-* edits, NOT pam-auth-update: our pwhistory edit already
		// counts as a "local modification" so pam-auth-update refuses common-* without --force, and
		// --force would drop our pwhistory line. We add only the preauth line (before pam_unix) and
		// the account line: neither shifts the post-pam_unix jump offsets (success=N), so the auth
		// stack stays correct; audit + even_deny_root satisfy the controls. SSH key auth bypasses
		// the password stack, so a slip here can't lock out key login.
		// The module args (deny/unlock_time/audit/even_deny_root) are policy: they come from the
		// rule data (params), with a safe default if the rule omits them.
		fl := faillockParams
		if fl == "" {
			fl = "audit silent deny=5 unlock_time=900 even_deny_root"
		}
		_, _ = fmt.Fprintf(&b, "execute 'pavois-faillock-preauth' do\n  command 'sed -ri \"/^auth.*pam_unix\\.so/i auth required pam_faillock.so preauth %s\" /etc/pam.d/common-auth'\n  only_if 'test -f /etc/pam.d/common-auth'\n  not_if 'grep -qE \"pam_faillock.so\" /etc/pam.d/common-auth'\nend\n\n", fl)
		b.WriteString("execute 'pavois-faillock-account' do\n  command 'printf \"account required pam_faillock.so\\n\" >> /etc/pam.d/common-account'\n  only_if 'test -f /etc/pam.d/common-account'\n  not_if 'grep -qE \"pam_faillock.so\" /etc/pam.d/common-account'\nend\n\n")
		n++
	}
	if selinuxWanted {
		// SELinux enforcing (RHEL/Alma/Fedora). Persist the config first so the mode survives a
		// reboot, then bump the LIVE state: but only from Permissive: `setenforce 1` errors when
		// SELinux booted Disabled, and flipping a Disabled system straight to enforcing without a
		// filesystem relabel can lock everyone out, so in that case we schedule an autorelabel and
		// leave the runtime change for the (admin-triggered) reboot. Every step is gated on
		// /etc/selinux/config existing, so the whole block no-ops on Debian/Ubuntu.
		b.WriteString("execute 'pavois-selinux-persist' do\n" +
			"  command \"sed -ri 's/^SELINUX=.*/SELINUX=enforcing/; s/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config\"\n" +
			"  only_if 'test -f /etc/selinux/config'\n" +
			"  not_if 'grep -qE \"^SELINUX=enforcing\" /etc/selinux/config'\nend\n\n")
		b.WriteString("execute 'pavois-selinux-enforce-now' do\n" +
			"  command 'setenforce 1'\n" +
			"  only_if 'test -f /etc/selinux/config && command -v getenforce >/dev/null 2>&1 && test \"$(getenforce)\" = \"Permissive\"'\nend\n\n")
		// Disabled -> enforcing needs a relabel + reboot to be safe; never setenforce from Disabled.
		b.WriteString("execute 'pavois-selinux-autorelabel' do\n" +
			"  command 'touch /.autorelabel'\n" +
			"  only_if 'test -f /etc/selinux/config && command -v getenforce >/dev/null 2>&1 && test \"$(getenforce)\" = \"Disabled\"'\nend\n\n")
		n++
	}
	if len(dconfEntries) > 0 {
		// GNOME dconf hardening: aggregate every enabled/compliant dconf control's key=value into
		// ONE keyfile (grouped by [section]) plus a locks file (so users can't override them) under
		// /etc/dconf/db/local.d, then `dconf update` to compile the binary db. The settings AND
		// their locks are RULE DATA: nothing GNOME-specific is hardcoded here, the engine only
		// groups keys by section. The checks grep BOTH the .d keyfile and the locks/ file.
		sections := map[string][]string{}
		var locks []string
		for _, key := range sortedKeysS(dconfEntries) {
			i := strings.LastIndex(key, "/")
			section, name := key[:i], key[i+1:]
			sections[section] = append(sections[section], name+"="+dconfEntries[key])
			locks = append(locks, "/"+key)
		}
		var secNames []string
		for sec := range sections {
			secNames = append(secNames, sec)
		}
		sort.Strings(secNames)
		var kf strings.Builder
		for i, sec := range secNames {
			if i > 0 {
				kf.WriteString("\n")
			}
			kf.WriteString("[" + sec + "]\n")
			for _, line := range sections[sec] {
				kf.WriteString(line + "\n")
			}
		}
		sort.Strings(locks)
		b.WriteString("directory '/etc/dconf/db/local.d/locks' do\n  recursive true\nend\n\n")
		_, _ = fmt.Fprintf(&b, "file '/etc/dconf/db/local.d/00-pavois-hardening' do\n  content %q\n  mode '0644'\nend\n\n", kf.String())
		_, _ = fmt.Fprintf(&b, "file '/etc/dconf/db/local.d/locks/00-pavois-locks' do\n  content %q\n  mode '0644'\nend\n\n", strings.Join(locks, "\n")+"\n")
		b.WriteString("execute 'pavois-dconf-update' do\n  command 'dconf update 2>/dev/null || true'\nend\n\n")
		n++
	}
	if kernelBuildWanted {
		// kconfig hardening can't be done at runtime: it needs a kernel built with the KSPP
		// options. Pavois DELIVERS the recipe (it does NOT run it: ~20GB disk, 30-60min, reboot,
		// the admin's call). The script bases on the running kernel's config and merges the options
		// Pavois's kconfig controls require. ARM64-only / removed options are filtered by the
		// controls' only_if guards, so they're never targeted here.
		// The recipe is DATA (docs/reference/kernel-build.sh), read at apply time and delivered
		// verbatim: never hardcoded here (engine, not content). Tests may pass an empty string.
		script := kernelRecipe
		if script == "" {
			script = "#!/bin/sh\necho 'pavois: kernel-build recipe missing (docs/reference/kernel-build.sh)' >&2; exit 1\n"
		}
		_, _ = fmt.Fprintf(&b, "file '/usr/local/sbin/pavois-harden-kernel.sh' do\n  content %q\n  owner 'root'\n  group 'root'\n  mode '0750'\nend\n\n", script)
		b.WriteString("log 'Pavois: KSPP kernel-build recipe DELIVERED at /usr/local/sbin/pavois-harden-kernel.sh: review and run it manually (heavy: ~20GB disk, 30-60min, reboot). Pavois does not run it for you; kconfig controls pass once you boot the rebuilt kernel.' do\n  level :warn\nend\n\n")
		n++
	}
	if len(manualFixes) > 0 {
		// Deliver (never run) the fixes that need judgement or are operationally risky, as one
		// reviewable script: same contract as the kernel-build recipe above.
		sort.Slice(manualFixes, func(i, j int) bool { return manualFixes[i].id < manualFixes[j].id })
		var sb strings.Builder
		sb.WriteString("#!/bin/sh\n")
		sb.WriteString("# Pavois: MANUAL hardening fixes. Pavois does NOT run these: each needs human\n")
		sb.WriteString("# judgement or is operationally risky. Review EACH block, then run the ones you want.\n\n")
		for _, mf := range manualFixes {
			sb.WriteString("# === " + mf.id + " ===\n")
			if mf.reason != "" {
				sb.WriteString("# " + mf.reason + "\n")
			}
			sb.WriteString(strings.TrimRight(mf.command, "\n") + "\n\n")
		}
		_, _ = fmt.Fprintf(&b, "file '/usr/local/sbin/pavois-manual-fixes.sh' do\n  content %q\n  owner 'root'\n  group 'root'\n  mode '0750'\nend\n\n", sb.String())
		_, _ = fmt.Fprintf(&b, "log 'Pavois: %d MANUAL fix(es) DELIVERED at /usr/local/sbin/pavois-manual-fixes.sh: review and run them yourself; Pavois will not (they need judgement or are risky).' do\n  level :warn\nend\n\n", len(manualFixes))
		n++
	}
	return b.String(), n, reboot, pendingEnabled, conflicts
}

func sortedAnyKeys(m map[string]any) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func sortedKeysS(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func sortedFileKeys(m map[string]map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func sshOptsFor(key string) []string {
	o := []string{"-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=15", "-F", "/dev/null"}
	if key != "" {
		o = append(o, "-i", key)
	}
	return o
}

func sshOpts() []string { return sshOptsFor(haKey) }

// sshTTY builds ssh args with a forced pseudo-tty (-tt) so `sudo` works even under
// `Defaults requiretty` (ANSSI BP-028 R39): Pavois can apply that control, so its own
// management path must survive it. Used for the sudo cinc-apply runs (not scp).
func sshTTY(target, cmd string) []string {
	return append(append(append([]string{"-tt"}, sshOpts()...), target), cmd)
}

// pavoisPrereqs are the tools PAVOIS needs on a target, as opposed to the packages the CONTROLS
// need (those are `requires_package`, collected into the plan's baseline_packages and installed by
// the apply itself).
//
// The distinction matters because of WHEN: the restore point is taken before a single resource
// converges, so anything it depends on has to be there already. tar is the case that surfaced, on
// AlmaLinux cloud images, which are minimal enough to ship without it.
var pavoisPrereqs = map[string]string{
	"tar":  "the restore point archive (harden rollback)",
	"gzip": "compressing that archive",
}

// rpmPrereqs are needed on EL and Fedora only. grubby is THE supported way to edit the kernel
// command line on a BLS system, and the cloud images are minimal enough to omit it: measured on a
// fresh AlmaLinux 10 VM, which has no grubby, no /boot/grub2/grub.cfg, and only the EFI wrapper
// that grub2-mkconfig refuses to overwrite. Without grubby there is no correct way to apply a
// cmdline change there at all, so the run stops before pretending otherwise.
var rpmPrereqs = map[string]string{
	"grubby": "editing the kernel command line (BLS entries)",
}

// prereqsFor returns what this OS needs: the common set, plus the RPM ones where they apply.
func prereqsFor(osName string) map[string]string {
	out := make(map[string]string, len(pavoisPrereqs)+len(rpmPrereqs))
	for k, v := range pavoisPrereqs {
		out[k] = v
	}
	switch {
	case strings.HasPrefix(osName, "rhel"), strings.HasPrefix(osName, "alma"),
		strings.HasPrefix(osName, "rocky"), strings.HasPrefix(osName, "fedora"):
		for k, v := range rpmPrereqs {
			out[k] = v
		}
	}
	return out
}

// missingPrereqs asks the target once for everything, rather than discovering the tools one
// failure at a time. Returns the missing binaries, sorted.
func missingPrereqs(target, osName string, opts []string) []string {
	want := prereqsFor(osName)
	var probe strings.Builder
	for tool := range want {
		fmt.Fprintf(&probe, "command -v %s >/dev/null 2>&1 || echo %s; ", tool, tool)
	}
	out, err := exec.Command("ssh", append(append(opts, target), probe.String())...).Output() //nolint:gosec // fixed args, operator target
	if err != nil {
		return nil // unreachable target: the caller's own connection error will say so better
	}
	var missing []string
	for _, line := range strings.Fields(string(out)) {
		if _, known := want[line]; known {
			missing = append(missing, line)
		}
	}
	sort.Strings(missing)
	return missing
}

// installPrereqs installs the missing tools with the target's own package manager. It is the same
// bargain pavois already makes for cinc-client, and it is announced on stderr rather than done
// quietly.
func installPrereqs(target, osName string, missing []string, sudoCmd func(string) string,
	run func(string) error,
) error {
	mgr := "DEBIAN_FRONTEND=noninteractive apt-get install -y"
	switch {
	case strings.HasPrefix(osName, "rhel"), strings.HasPrefix(osName, "alma"),
		strings.HasPrefix(osName, "rocky"), strings.HasPrefix(osName, "fedora"):
		mgr = "dnf install -y"
	}
	return run(sudoCmd(mgr + " " + strings.Join(missing, " ")))
}

// prereqError explains what is missing, why pavois wants it, and how to install it, naming the
// package manager rather than making the operator guess which distro convention applies.
func prereqError(osName string, missing []string) error {
	installer := "apt-get install -y"
	switch {
	case strings.HasPrefix(osName, "rhel"), strings.HasPrefix(osName, "alma"),
		strings.HasPrefix(osName, "rocky"), strings.HasPrefix(osName, "fedora"):
		installer = "dnf install -y"
	}
	var why strings.Builder
	for _, m := range missing {
		fmt.Fprintf(&why, "\n    %-7s %s", m, prereqsFor(osName)[m])
	}
	return fmt.Errorf("the target is missing what pavois needs to operate:%s\n\n"+
		"  Install them:  sudo %s %s\n"+
		"  Or skip the restore point with --no-restore-point, and lose `harden rollback`",
		why.String(), installer, strings.Join(missing, " "))
}

func runHardenApply(cmd *cobra.Command, args []string) error {
	raw, err := os.ReadFile(args[0])
	if err != nil {
		return err
	}
	var p planFile
	if err := yaml.Unmarshal(raw, &p); err != nil {
		return fmt.Errorf("parse plan: %w", err)
	}
	auditRules, _ := os.ReadFile(filepath.Join(findRoot(), "docs", "reference", "audit.rules"))
	// The kernel-build recipe is DATA, one script per OS/version under docs/reference/kernel-build/
	// (each tailored to its distro + kernel: apt bindeb-pkg vs dnf rpmbuild, version quirks). Pick
	// the target's; fall back to the legacy single kernel-build.sh if a per-OS file is absent.
	kernelRecipe, _ := os.ReadFile(filepath.Join(findRoot(), "docs", "reference", "kernel-build", p.OS+".sh"))
	if len(kernelRecipe) == 0 {
		kernelRecipe, _ = os.ReadFile(filepath.Join(findRoot(), "docs", "reference", "kernel-build.sh"))
	}
	out := cmd.OutOrStdout()

	// Danger gate: an enabled remediation flagged `danger:` can brick or lock out the
	// host. Refuse to converge it unless the operator acknowledged the risk: either
	// per-item (`acknowledged: true` in the plan) or run-wide (--i-understand-danger).
	var unacked []string
	for id, r := range p.Rules {
		enabled := r.Apply != nil && *r.Apply
		acked := haIUnderstandDanger || (r.Acknowledged != nil && *r.Acknowledged)
		if enabled && r.Danger != "" && !acked {
			unacked = append(unacked, fmt.Sprintf("    - %s\n        ⚠ %s", id, r.Danger))
		}
	}
	if len(unacked) > 0 {
		sort.Strings(unacked)
		_, _ = fmt.Fprintln(out, "pavois: ✗ refusing to apply: dangerous remediation(s) not acknowledged:")
		for _, u := range unacked {
			_, _ = fmt.Fprintln(out, u)
		}
		return fmt.Errorf("%d dangerous item(s) enabled without acknowledgement; set `acknowledged: true` on each in the plan, or re-run with --i-understand-danger", len(unacked))
	}
	// Subset-plan guard: aggregated drop-ins (sshd/sysctl/cmdline/keyval) are rewritten
	// wholesale and stay complete only by re-emitting the COMPLIANT siblings present in the
	// plan. A hand-made partial plan (only a few rules) regenerates the drop-in WITHOUT the
	// missing controls, silently regressing dozens. Warn loudly if the plan looks like a subset.
	aggEnabled := 0
	for _, r := range p.Rules {
		if r.Apply != nil && *r.Apply && r.Remediation != nil {
			switch s(r.Remediation["resource"]) {
			case "sshd_setting", "sysctl", "kernel_cmdline", "keyval":
				aggEnabled++
			}
		}
	}
	if aggEnabled > 0 && len(p.Rules) < 100 {
		_, _ = fmt.Fprintf(out, "pavois: ⚠ this plan has only %d rules and enables aggregated remediations "+
			"(sshd/sysctl/cmdline/keyval). Those drop-ins are rewritten in full: applying a SUBSET "+
			"plan wipes the sibling controls not listed here (e.g. re-enables root SSH, drops sysctls). "+
			"Apply the FULL `harden plan` output, or use `scan --controls` to test one control.\n", len(p.Rules))
	}
	// If a grub_password remediation is enabled, generate a strong secret and store it in a
	// local 0600 vault BEFORE compiling: the recipe sets the (salted) hash on the target.
	grubPassword := ""
	for _, r := range p.Rules {
		if r.Apply != nil && *r.Apply && r.Remediation != nil && s(r.Remediation["resource"]) == "grub_password" {
			grubPassword = genPassword(24)
			if !haDryRun { // only persist the secret on a real apply, never on a preview
				if path, err := vaultStore(findRoot(), p.Target, "grub", grubPassword); err == nil {
					_, _ = fmt.Fprintf(out, "pavois: 🔐 grub password generated and vaulted at %s (keep it safe)\n", path)
				} else {
					return fmt.Errorf("vault grub password: %w", err)
				}
			}
			break
		}
	}
	recipe, count, reboot, pending, conflicts := compileRecipe(p, string(auditRules), string(kernelRecipe), grubPassword, haStandard)
	if len(conflicts) > 0 {
		_, _ = fmt.Fprintln(out, "pavois: ✗ conflicting remediations: refusing to apply:")
		for _, c := range conflicts {
			_, _ = fmt.Fprintf(out, "    - %s\n", c)
		}
		return fmt.Errorf("%d remediation conflict(s); resolve them in the plan (disable one side, or set a choice) and retry", len(conflicts))
	}
	if pending > 0 {
		_, _ = fmt.Fprintf(out, "pavois: ⚠ %d enabled rule(s) have no remediation yet (pending): they are skipped, nothing is generated for them.\n", pending)
	}
	_, _ = fmt.Fprintf(out, "pavois: compiled %d enabled item(s) into native Chef resources:\n\n%s\n", count, recipe)
	if reboot {
		if haReboot {
			// Reboot is a Chef action, not an out-of-band step. NB: the `reboot` resource's
			// :reboot_now is a no-op under cinc-apply (chef-apply doesn't run the reboot
			// handler a full chef-client run would), so issue it with an `execute` LAST:
			// every change applies first, then the box reboots in-run (activates audit=1).
			recipe += "# pavois: reboot in-run to activate kernel cmdline (audit=1) / modules / sysctl\n" +
				"execute 'pavois-reboot' do\n  command 'systemctl reboot'\nend\n"
			_, _ = fmt.Fprintln(out, "pavois: ⚠ changes need a REBOOT: Pavois will reboot the target via Chef at the end of the run.")
		} else {
			_, _ = fmt.Fprintln(out, "pavois: ⚠ some enabled changes need a REBOOT to take effect (kernel cmdline/module); re-run with --reboot, or reboot the target yourself.")
		}
	}
	if count == 0 {
		_, _ = fmt.Fprintln(out, "pavois: nothing enabled (no apply: true). Edit the plan and retry.")
		return nil
	}
	if haDryRun {
		_, _ = fmt.Fprintln(out, "pavois: --dry-run, not converging.")
		return nil
	}
	target := p.Target
	if haTarget != "" {
		target = haTarget
	}
	if target == "" {
		return fmt.Errorf("no target in plan (use --target)")
	}
	if haReboot {
		if _, tr := machineTransport(target); tr == "local://" {
			return fmt.Errorf("--reboot refuses a local target (%q): it would reboot THIS machine. "+
				"Reboot a remote/VM target instead, or reboot the host yourself", target)
		}
	}

	tmp, err := os.CreateTemp("", "pavois-harden-*.rb")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(tmp.Name()) }()
	if _, err := tmp.WriteString(recipe); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close temp recipe: %w", err)
	}

	run := func(name string, a ...string) error {
		c := exec.Command(name, a...)
		c.Stdout, c.Stderr = os.Stderr, os.Stderr
		return c.Run()
	}
	// Least-privilege target account (no NOPASSWD): the converge runs `sudo cinc-apply`
	// on the target, so the sudo password must reach it. resolveSudoPass reads --sudo-prompt
	// (no-echo) or PAVOIS_SUDO_PASSWORD; empty means NOPASSWD (unchanged behaviour).
	sudoPass, err := resolveSudoPass(haSudoPrompt)
	if err != nil {
		return fmt.Errorf("read sudo password: %w", err)
	}
	// sudoCmd prefixes a remote command with sudo, using `-S` (read the password from stdin)
	// when we have one. runSudoTTY runs it over ssh -tt (pty for `Defaults requiretty`) and
	// feeds the password to stdin: NEVER argv, so it can't leak via `ps` on host or target.
	sudoCmd := func(rest string) string {
		if sudoPass != "" {
			return "sudo -S " + rest
		}
		return "sudo " + rest
	}
	// cinc-apply needs a controlling terminal (-tt) to actually CONVERGE: without one it runs but
	// applies nothing (silent no-op). But `ssh -tt` + a naked piped password races the pty line
	// discipline and `sudo -S` times out on rhel9. So: force -tt for the tty, but READ the password
	// from ssh-stdin into a shell var first (draining the pty) and feed it to `sudo -S` via a bash
	// here-string: no race, and the password never reaches argv. Empty sudoPass (NOPASSWD) just
	// leaves __P empty, which sudo ignores.
	runSudoTTY := func(remote string) error {
		wrapped := "IFS= read -r __P; " + remote + " <<<\"$__P\""
		args := append(append([]string{"-tt"}, sshOpts()...), target, wrapped)
		c := exec.Command("ssh", args...) //nolint:gosec // fixed args, operator target
		c.Stdout, c.Stderr = os.Stderr, os.Stderr
		if sudoPass != "" {
			c.Stdin = strings.NewReader(sudoPass + "\n")
		}
		return c.Run()
	}
	// capture runs a read-only command on the target over raw ssh and returns its trimmed
	// stdout (used for the reboot proof: boot_id is world-readable, no sudo needed).
	capture := func(remote string) string {
		c := exec.Command("ssh", append(append(sshOpts(), target), remote)...) //nolint:gosec // fixed args, operator target
		o, _ := c.Output()
		return strings.TrimSpace(string(o))
	}
	// Ask once, up front, for everything pavois itself needs on the target. Before the cinc
	// bootstrap on purpose: refusing to proceed AFTER installing 200 MB of Ruby on someone's
	// machine is a poor way to say "you are missing tar".
	if !haNoRestorePoint {
		if missing := missingPrereqs(target, p.OS, sshOpts()); len(missing) > 0 {
			// Install them, rather than sending the operator away to do it by hand. pavois already
			// installs cinc-client on this target, on the next line: refusing to add tar while
			// installing 200 MB of Ruby would be a strange place to draw the line, and it leaves
			// every EL target unusable (the AlmaLinux cloud images ship without tar).
			_, _ = fmt.Fprintf(os.Stderr, "pavois: installing what it needs on %s: %s\n",
				target, strings.Join(missing, " "))
			if err := installPrereqs(target, p.OS, missing, sudoCmd, runSudoTTY); err != nil {
				return fmt.Errorf("%w\n\n%w", err, prereqError(p.OS, missing))
			}
			if still := missingPrereqs(target, p.OS, sshOpts()); len(still) > 0 {
				return prereqError(p.OS, still)
			}
		}
	}

	_, _ = fmt.Fprintf(os.Stderr, "pavois: ensuring cinc-client on %s…\n", target)
	// FIRST check presence with NO sudo: a hardened target (use_pty) blocks a naked non-tty sudo,
	// so we must never need sudo just to CHECK (that breaks the post-harden re-apply). Only if
	// cinc-apply is genuinely absent do we sudo-install it: as root (sudo first), download the
	// installer to a FILE then run it (a `curl | bash` pipe / nested sudo wedges), over ssh WITHOUT
	// -tt and piping the password (an -tt pty races `sudo -S` on rhel9). Password never hits argv.
	if err := exec.Command("ssh", append(append(sshOpts(), target), "command -v cinc-apply >/dev/null 2>&1")...).Run(); err != nil { //nolint:gosec // fixed args, operator target
		ensure := sudoCmd("bash -c 'curl -fsSL https://omnitruck.cinc.sh/install.sh -o /tmp/pavois-cinc-install.sh && sh /tmp/pavois-cinc-install.sh -P cinc'")
		ec := exec.Command("ssh", append(append(sshOpts(), target), ensure)...) //nolint:gosec // fixed args, operator target
		ec.Stdout, ec.Stderr = os.Stderr, os.Stderr
		if sudoPass != "" {
			ec.Stdin = strings.NewReader(sudoPass + "\n")
		}
		if err := ec.Run(); err != nil {
			return fmt.Errorf("install cinc-client: %w", err)
		}
	}
	// PHOTOGRAPH THE PRIOR STATE, before a single resource converges. The plan is declarative, so
	// what the run will touch is knowable in advance: every file it writes, every package it
	// installs, every service it enables. That is exactly what `harden rollback` needs, and no other
	// hardening tool captures it (oscap hands you a bash script; Lynis only advises).
	if !haNoRestorePoint {
		dir := haRestorePoint
		if dir == "" {
			dir = filepath.Join(findRoot(), "restore-points",
				fmt.Sprintf("%s-%s", strings.NewReplacer("@", "_", ".", "-", ":", "-").Replace(target),
					time.Now().UTC().Format("20060102-1504")))
		}
		_, _ = fmt.Fprintln(os.Stderr, "pavois: photographing the prior state (restore point)…")
		if got, err := writeRestorePoint(p, recipe, target, args[0], dir, sshOpts(), sudoPass); err != nil {
			return fmt.Errorf("restore point: %w (re-run with --no-restore-point to skip, but you lose the rollback)", err)
		} else {
			_, _ = fmt.Fprintf(out, "pavois: 📸 restore point → %s   (undo with: pavois harden rollback %s --yes)\n", got, got)
		}
	}

	_, _ = fmt.Fprintln(os.Stderr, "pavois: copying recipe…")
	if err := // -O: the legacy SCP protocol, over an exec channel. Modern scp speaks SFTP by default,
		// and a stock debian13 (OpenSSH 10) declares no `Subsystem sftp`, so an sftp transfer dies
		// with "subsystem request failed on channel 0" — measured on a fresh VM. -O needs no
		// subsystem and works on every target we support.
		run("scp", append(append([]string{"-O"}, append(sshOpts(), tmp.Name())...), target+":/tmp/pavois-harden.rb")...); err != nil {
		return fmt.Errorf("copy recipe: %w", err)
	}

	// Refresh the apt cache on the target BEFORE cinc-apply compiles the recipe. Chef's
	// apt_package reads the candidate version at compile time (load_current_resource); on a
	// stale cache that is "no candidate" and, with ignore_failure, the package silently never
	// installs. An in-recipe `apt-get update` execute runs too late (converge, after compile).
	// Self-guarded so it is a no-op on dnf/zypper hosts.
	// Heal an interrupted dpkg BEFORE touching apt. A prior aborted install (a killed run, a
	// power loss) leaves dpkg half-configured; then EVERY apt operation fails with exit 100
	// ("dpkg was interrupted, you must manually run 'sudo dpkg --configure -a'"), which cascades
	// through the converge and aborts it on the first package. `dpkg --configure -a` is idempotent
	// (a no-op when clean), so we run it only when `dpkg --audit` reports a broken state: and say
	// so, instead of surfacing the cryptic exit-100 stacktrace later.
	if capture("command -v dpkg >/dev/null 2>&1 && dpkg --audit 2>/dev/null | grep -q . && echo broken") == "broken" {
		_, _ = fmt.Fprintln(os.Stderr, "pavois: dpkg is in an interrupted state (a prior install was cut short): repairing with 'dpkg --configure -a' before continuing…")
		if err := runSudoTTY(sudoCmd("DEBIAN_FRONTEND=noninteractive dpkg --configure -a")); err != nil {
			return fmt.Errorf("dpkg is interrupted on %s and auto-repair failed; run 'sudo dpkg --configure -a' on the target, then retry: %w", target, err)
		}
	}

	_, _ = fmt.Fprintln(os.Stderr, "pavois: refreshing apt cache…")
	_ = runSudoTTY("if command -v apt-get >/dev/null 2>&1; then " + sudoCmd("env APT_LISTBUGS_FRONTEND=none apt-get update -qq") + " || true; fi")

	// Terraform-style: show the REAL diff (why-run changes nothing) before asking.
	_, _ = fmt.Fprintf(out, "\npavois: planned changes on %s (nothing applied yet):\n\n", target)
	// APT_LISTBUGS_FRONTEND=none: if apt-listbugs is (being) installed, its apt hook otherwise
	// ABORTS every non-interactive apt operation in the converge (it can't prompt), which makes
	// the other package installs fail. Setting it none makes apt-listbugs a no-op for THIS
	// converge only; a normal admin `apt install` later still gets its critical-bug warnings.
	why := sudoCmd("env CHEF_LICENSE=accept-silent APT_LISTBUGS_FRONTEND=none cinc-apply /tmp/pavois-harden.rb --why-run")
	if err := runSudoTTY(why); err != nil {
		return fmt.Errorf("why-run: %w", err)
	}

	if !haYes {
		_, _ = fmt.Fprint(out, "\nApply these changes? [y/N]: ")
		ans, _ := bufio.NewReader(os.Stdin).ReadString('\n')
		if a := strings.ToLower(strings.TrimSpace(ans)); a != "y" && a != "yes" {
			_, _ = fmt.Fprintln(out, "pavois: aborted: nothing applied.")
			return nil
		}
	}

	// Reboot proof: snapshot the boot_id BEFORE the run reboots the box, so we can later
	// show the post-reboot boot_id differs (the re-scan really ran on a fresh boot).
	bootBefore := ""
	if reboot && haReboot {
		bootBefore = capture("cat /proc/sys/kernel/random/boot_id")
	}

	_, _ = fmt.Fprintln(os.Stderr, "pavois: converging (cinc-apply)…")
	conv := sudoCmd("env CHEF_LICENSE=accept-silent APT_LISTBUGS_FRONTEND=none cinc-apply /tmp/pavois-harden.rb")
	if err := runSudoTTY(conv); err != nil {
		// With --reboot the run ends by rebooting the box: the SSH session drops mid-run,
		// which surfaces as a non-zero exit. That's expected: wait for the box to return.
		if !reboot || !haReboot {
			return fmt.Errorf("converge: %w", err)
		}
	}
	// SELinux (rhel/fedora): a config that cinc-apply writes via atomic temp+rename can inherit the
	// wrong type (tmp_t/etc_t) instead of the target's, so a confined daemon IGNORES it: sshd skips
	// a mislabeled drop-in and the whole harden silently has NO effect (grade unchanged). Relabel
	// /etc so every dropped file gets its correct context. No-op off SELinux.
	_ = runSudoTTY(sudoCmd("sh -c 'selinuxenabled 2>/dev/null && command -v restorecon >/dev/null 2>&1 && restorecon -R /etc 2>/dev/null; true'"))
	if reboot && haReboot {
		// Like Ansible's reboot module (wait_for_connection): wait for the connection to
		// DROP (box going down), then for it to come back: a plain re-ping right away
		// would false-positive on the still-up box before it actually reboots.
		ping := func() bool {
			c := exec.Command("ssh", append(append(sshOpts(), target), "true")...) // quiet
			return c.Run() == nil
		}
		_, _ = fmt.Fprintln(os.Stderr, "pavois: waiting for the target to reboot…")
		for i := 0; i < 24 && ping(); i++ { // wait until it goes down (~2min max)
			time.Sleep(5 * time.Second)
		}
		up := false
		for i := 0; i < 40; i++ { // wait until it comes back (~4min max)
			time.Sleep(6 * time.Second)
			if ping() {
				up = true
				break
			}
		}
		if !up {
			return fmt.Errorf("target did not come back after reboot within ~4min")
		}
		_, _ = fmt.Fprintln(os.Stderr, "pavois: target back up after reboot.")
		writeRebootProof(out, target, bootBefore, capture)
	}
	_, _ = fmt.Fprintln(out, "\npavois: converged.")
	if !haScan {
		_, _ = fmt.Fprintf(out, "Pavois: re-scan to confirm: bin/pavois scan %s --key … --sudo\n", target)
		return nil
	}

	// --scan: close the loop: re-scan, fresh report, new grade.
	root := findRoot()
	machine, transport := machineTransport(target)
	_ = os.MkdirAll(filepath.Join(root, "reports"), 0o750)
	jsonPath := filepath.Join(root, "reports", fmt.Sprintf("rapport-%s-%s-%s.json",
		slug(machine), strings.TrimSuffix(transport, "://"), time.Now().Format("20060102-150405")))
	_, _ = fmt.Fprintln(os.Stderr, "Pavois: re-scanning…")
	if _, err := engine.Run(engine.Options{
		Root: root, Target: target, Profile: "linux/" + p.OS, Engine: "auto",
		Key: haKey, Sudo: true, JSONOut: jsonPath,
		// The converge just used this password for every sudo it ran; dropping it here made the
		// run fail at its last step on any password-sudo host: after the box was already
		// hardened, and with no report to show for it.
		SudoPass: sudoPass,
		// re-scan ON the target for ssh (like harden plan): a real pty so sudo works under
		// Defaults use_pty, and raw ssh that uses ~/.ssh defaults instead of failing when no
		// --key/agent key reaches cinc's train-ssh transport. On-target sudo assumes NOPASSWD,
		// so when a password is supplied we take the native SSH transport instead: the same
		// arbitration harden plan makes.
		OnTarget: strings.Contains(target, "@") && sudoPass == "",
	}); err != nil {
		return err
	}
	rep, err := audit.Load(jsonPath)
	if err != nil {
		return err
	}
	htmlPath := strings.TrimSuffix(jsonPath, ".json") + ".html"
	htmlStr, nctrl, nnorm := render.HTML(rep, render.Meta{
		Machine: machine, Transport: transport,
		Timestamp: time.Now().Format("2006-01-02 15:04:05 MST"),
		Engine:    "CINC Auditor (InSpec)",
	})
	_ = os.WriteFile(htmlPath, []byte(htmlStr), 0o600)
	res := audit.Evaluate(rep, machine, "", "")
	_, _ = fmt.Fprintf(out, "pavois: report %s (%d controls, %d standards)\n", htmlPath, nctrl, nnorm)
	if nnorm > 0 {
		letter, pts, _ := audit.GradeResult(res)
		writeScorecard(out, letter, pts, res.Passed, res.Total, res.Qualified, res.Waived, res.NotApplicable)
	}

	// Validate every applied remediation actually made its control PASS: a remediation
	// that converged but left the control failing is broken (or needs a reboot/config).
	var scan2 inspecScan
	if raw, err := os.ReadFile(jsonPath); err == nil {
		_ = json.Unmarshal(raw, &scan2)
	}
	st2 := map[string]string{}
	for _, pr := range scan2.Profiles {
		for _, c := range pr.Controls {
			st2[c.ID] = controlStatus(c.Results)
		}
	}
	applied, passed := 0, 0
	var failed []string
	for cid, r := range p.Rules {
		if r.Apply != nil && *r.Apply && r.Remediation != nil {
			applied++
			if st2[cid] == "compliant" {
				passed++
			} else {
				failed = append(failed, cid)
			}
		}
	}
	if applied > 0 {
		// When a real reboot happened, the re-scan ran AFTER it: so a PASS is reboot-proven
		// (the change survived the reboot), not just live. That's the empirical persistence proof.
		proven := ""
		if reboot && haReboot {
			proven = ": re-scanned after a real reboot, so these passes are reboot-proven"
		}
		_, _ = fmt.Fprintf(out, "\npavois: remediation check: %d/%d applied controls now PASS%s.\n", passed, applied, proven)
		if len(failed) > 0 {
			sort.Strings(failed)
			_, _ = fmt.Fprintf(out, "pavois: ⚠ %d did NOT pass (broken remediation, or needs reboot/config: investigate):\n", len(failed))
			for _, c := range failed {
				_, _ = fmt.Fprintf(out, "    - %s\n", c)
			}
		}
	}

	// A plan is a snapshot of the system BEFORE hardening: but hardening MUTATES the system.
	// pavois installs the packages a control needs to be meaningful (`requires_package`), and a
	// package brings its own files, units and defaults with it: installing `at` creates
	// /etc/at.deny (which another control requires to be ABSENT), installing an MTA brings its
	// banner and VRFY defaults into scope. Those controls were compliant or not-applicable when
	// the plan was computed, so nothing ever remediated them, and a single apply can never close
	// them. Name them, and say how to converge.
	var emerged []string
	for cid, r := range p.Rules {
		if st2[cid] == "gap" && r.Status != "gap" {
			emerged = append(emerged, cid)
		}
	}
	if len(emerged) > 0 {
		sort.Strings(emerged)
		_, _ = fmt.Fprintf(out, "\npavois: ⚠ %d control(s) became applicable DURING this run and were not in the plan\n"+
			"    (hardening installed packages that brought new files/units into scope):\n", len(emerged))
		for _, c := range emerged {
			_, _ = fmt.Fprintf(out, "    - %s\n", c)
		}
		_, _ = fmt.Fprintf(out, "    Converge: re-plan from the CURRENT state and apply again, until a pass has\n"+
			"    nothing left to do: pavois harden plan %s --sudo --from <this report>\n", target)
	}
	return nil
}

// writeRebootProof captures the post-reboot boot_id + uptime and writes a reboot-proof
// artifact: evidence that the re-scan really ran on a fresh boot (boot_id changed), so a
// PASS after `--reboot --scan` is empirically reboot-survivable. Feed it to `pavois bundle
// --reboot-proof`. boot_id is world-readable, so no sudo is needed.
func writeRebootProof(out io.Writer, target, bootBefore string, capture func(string) string) {
	bootAfter := capture("cat /proc/sys/kernel/random/boot_id")
	uptime := capture("cat /proc/uptime")
	if i := strings.IndexByte(uptime, ' '); i > 0 {
		uptime = uptime[:i]
	}
	rebooted := bootBefore != "" && bootAfter != "" && bootBefore != bootAfter
	proof := map[string]any{
		"format":         "pavois-reboot-proof/v1",
		"target":         target,
		"captured_at":    time.Now().UTC().Format(time.RFC3339),
		"boot_id_before": bootBefore,
		"boot_id_after":  bootAfter,
		"rebooted":       rebooted,
		"uptime_seconds": uptime,
		"boot_time":      capture("uptime -s"),
	}
	root := findRoot()
	machine, transport := machineTransport(target)
	_ = os.MkdirAll(filepath.Join(root, "reports"), 0o750)
	path := filepath.Join(root, "reports", fmt.Sprintf("reboot-proof-%s-%s-%s.json",
		slug(machine), strings.TrimSuffix(transport, "://"), time.Now().Format("20060102-150405")))
	blob, _ := json.MarshalIndent(proof, "", "  ")
	if err := os.WriteFile(path, blob, 0o600); err != nil {
		return
	}
	short := func(s string) string {
		if len(s) > 8 {
			return s[:8]
		}
		return s
	}
	if rebooted {
		_, _ = fmt.Fprintf(out, "pavois: reboot proven (boot_id %s → %s) → %s\n", short(bootBefore), short(bootAfter), path)
	} else {
		_, _ = fmt.Fprintf(out, "pavois: reboot proof written (boot_id unchanged: verify) → %s\n", path)
	}
}

// genPassword returns a strong random password (crypto/rand) for pavois-managed secrets
// (e.g. the grub bootloader password). Ambiguous characters are excluded.
func genPassword(n int) string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#%^*-_=+"
	b := make([]byte, n)
	if _, err := crand.Read(b); err != nil {
		return ""
	}
	for i := range b {
		b[i] = chars[int(b[i])%len(chars)]
	}
	return string(b)
}

// vaultStore writes a generated secret to a local 0600 vault under <root>/.pavois-vault
// (gitignored). It's the admin's copy of secrets Pavois set on a target (it can't read them
// back, e.g. the grub pbkdf2 hash). Returns the file path.
func vaultStore(root, target, kind, secret string) (string, error) {
	host := target
	if i := strings.Index(target, "@"); i >= 0 {
		host = target[i+1:]
	}
	dir := filepath.Join(root, ".pavois-vault")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(dir, fmt.Sprintf("%s-%s.txt", kind, slug(host)))
	body := fmt.Sprintf("# Pavois %s secret for %s: keep safe, Pavois cannot recover it.\n%s\n", kind, target, secret)
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		return "", err
	}
	return path, nil
}
