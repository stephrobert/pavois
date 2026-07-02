package cmd

import (
	"bufio"
	crand "crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
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
	hardenPlanCmd.Flags().StringVar(&hdSSHPass, "ssh-pass", "", "SSH password (discouraged — leaks via ps/history; prefer --ssh-prompt or a key)")
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
// (e.g. /etc/audit/auditd.conf) — replace the line if present, append if missing, vs the
// keyval resource which rewrites the whole drop-in file.
type confLine struct{ file, key, value, reload, sep string } // sep "space" for login.defs (KEY VALUE), else "key = value"

// pamLine inserts a full PAM stack line before an anchor pattern (so module order is correct,
// e.g. pam_pwhistory before pam_unix in the password stack), skipped if the module is already
// present. Used for /etc/pam.d/common-* where ordering matters and a blind append is wrong.
type pamLine struct{ file, module, before, line string }

// execRem is a guarded shell command for cases no declarative resource fits cleanly — e.g.
// chmod over a glob (/etc/ssh/*.pub, /boot/System.map-*). not_if keeps it idempotent.
type execRem struct{ name, command, notIf string }

// manualFix is a remediation Pavois DELIVERS as a reviewable script but NEVER runs itself —
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
func compileRecipe(p planFile, auditRules, grubPassword, std string) (string, int, bool, int, []string) {
	var b strings.Builder
	b.WriteString("# Generated by `pavois harden apply` — native Chef resources, no bash.\n")
	b.WriteString("# Idempotent and batched. Apply with cinc-apply.\n\n")
	reboot := false
	pendingEnabled := 0
	auditRuleset := false
	noexecUser := "" // set when sudo-noexec is applied -> exempt the mgmt user (below)
	var conflicts []string

	inst := map[string]bool{}
	rm := map[string]bool{}
	sysctl := map[string]string{}             // key -> value
	sshd := map[string]string{}               // directive -> value
	svc := map[string]string{}                // service -> "action[…]"
	files := map[string]map[string]string{}   // path -> attr -> value
	dirs := map[string]map[string]string{}    // directory path -> attr -> value (mode/owner/group)
	keyvals := map[string]map[string]string{} // config file -> key -> value (drop-in, whole-file)
	confLines := []confLine{}                 // in-place key=value edits in a shared file (auditd.conf)
	pamLines := []pamLine{}                   // PAM stack lines inserted before an anchor (idempotent)
	execs := []execRem{}                      // arbitrary guarded command (e.g. chmod on a glob)
	kmods := map[string]bool{}
	cmdline := map[string]bool{}     // kernel cmdline params -> one grub drop-in
	mounts := map[string]*mountAgg{} // mount point -> aggregated tmpfs options (all-or-nothing)
	fwEnableCmd := ""                // firewall: open SSH then enable (no lockout), emitted once
	fwNftConfig := ""                // native nftables ruleset (hardened-kernel friendly), emitted once
	grubPwWanted := false            // a grub_password remediation was enabled
	dconfWanted := false             // a dconf (GNOME) remediation was enabled
	faillockWanted := false          // a pam_faillock remediation was enabled
	kernelBuildWanted := false       // a kernel_build remediation was enabled (deliver the recipe)
	manualFixes := []manualFix{}     // `manual` remediations — delivered as a script, never auto-run

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
	for cid, r := range p.Rules {
		enabled := r.Apply != nil && *r.Apply
		res := ""
		if r.Remediation != nil {
			res = s(r.Remediation["resource"])
		}
		// Aggregated drop-ins (sysctl/sshd/cmdline/keyval/mount) are all-or-nothing: regenerating
		// one from only the enabled gaps would DROP compliant controls' settings and regress them
		// (e.g. wipe /etc/sysctl.d/zz-pavois.conf down to the one gap, re-enable root SSH). So also
		// pull in COMPLIANT aggregated controls — the drop-in then holds the complete desired
		// state. They contribute their setting only (no pkg/reboot side effects).
		aggregated := res == "sysctl" || res == "sshd_setting" || res == "kernel_cmdline" || res == "keyval" || res == "mount"
		keepCompliant := aggregated && !enabled && r.Status == "compliant"
		if !enabled && !keepCompliant {
			continue
		}
		if enabled { // side effects only for controls we are actively fixing
			// rule dependency: a prerequisite package must be present first (e.g. the audit
			// ruleset needs auditd, which owns /etc/audit/rules.d/) — emitted before files.
			if r.RequiresPackage != "" {
				inst[r.RequiresPackage] = true
			}
			// `Defaults noexec` severs Pavois's own sudo→cinc path — self-exempt (below).
			if cid == "sudo-noexec" {
				if i := strings.Index(p.Target, "@"); i > 0 {
					noexecUser = p.Target[:i]
				}
			}
		}
		if r.Remediation == nil {
			if enabled {
				pendingEnabled++ // enabled but no remediation yet — don't skip silently
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
		// misc-sshd-limit-user-access is manual by default (which users/groups may SSH is
		// site-specific, Pavois cannot guess it). If the operator listed them in the plan,
		// enforce AllowUsers/AllowGroups as an sshd drop-in instead of a manual script.
		// NB: the list MUST include the account Pavois connects as, or SSH locks out.
		if enabled && cid == "misc-sshd-limit-user-access" && (len(r.SSHAllowUsers) > 0 || len(r.SSHAllowGroups) > 0) {
			if len(r.SSHAllowUsers) > 0 {
				setKV(sshd, "allowusers", strings.Join(r.SSHAllowUsers, " "), "sshd")
			}
			if len(r.SSHAllowGroups) > 0 {
				setKV(sshd, "allowgroups", strings.Join(r.SSHAllowGroups, " "), "sshd")
			}
			continue
		}
		switch res {
		case "choose":
			// "<group>-present" gap: the admin picked a technology to set up
			opts, _ := m["options"].(map[string]any)
			if o, ok := opts[r.Choose].(map[string]any); ok {
				inst[s(o["package"])] = true
				// Firewall policy (the nftables ruleset, the ufw command sequence) lives in the
				// rule as DATA — see the `ruleset`/`enable_cmd` fields on the option. Here we only
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
			dconfWanted = true // deploy the GNOME dconf hardening db (keyfile + locks) once, below
		case "pam_faillock":
			faillockWanted = true // enable account lockout via pam-auth-update profile, below
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
					setKV(files[path], path+"#"+k, s(v), "file "+k)
					files[path][k] = s(v)
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
	// One resource per package, each ignore_failure: cross-OS lists carry names absent here (RHEL
	// httpd/bind...) or virtual packages (telnet/ftp) that error; a batch would abort the whole run
	// on the first, and the real packages would never be installed/removed. Individual keeps them
	// independent — the present ones apply, the rest report failed without breaking the converge.
	for _, name := range sortedKeys(inst) {
		_, _ = fmt.Fprintf(&b, "package %q do\n  action :install\n  ignore_failure true\nend\n\n", name)
		n++
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
		// failing in the re-scan — it must NOT abort the whole converge and regress the host.
		_, _ = fmt.Fprintf(&b, "execute 'pavois-firewall-enable' do\n  command %q\n  ignore_failure true\n  not_if '/usr/sbin/ufw status 2>/dev/null | grep -q \"Status: active\"'\nend\n\n", fwEnableCmd)
		n++
	}
	if fwNftConfig != "" { // native nftables: write the ruleset, load it, enable the unit
		// ignore_failure on the load+service: a bad ruleset or missing package leaves the firewall
		// control failing (visible in the re-scan), never aborts the run.
		_, _ = fmt.Fprintf(&b, "file '/etc/nftables.conf' do\n  content %q\n  mode '0600'\nend\n\n", fwNftConfig)
		_, _ = fmt.Fprintf(&b, "execute 'pavois-nft-load' do\n  command 'nft -f /etc/nftables.conf'\n  ignore_failure true\n  subscribes :run, 'file[/etc/nftables.conf]', :immediately\nend\n\n")
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
		// net.ipv4.conf.all/default keys (log_martians, rp_filter…) to the kernel default —
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
		_, _ = fmt.Fprintf(&b, "service %q do\n  action [%s]\n  only_if \"systemctl cat %s.service >/dev/null 2>&1\"\nend\n\n", k, svc[k], k)
		n++
	}
	for _, mod := range sortedKeys(kmods) {
		_, _ = fmt.Fprintf(&b, "file %q do\n  content \"install %s /bin/true\\nblacklist %s\\n\"\nend\n\n",
			"/etc/modprobe.d/pavois-"+mod+".conf", mod, mod)
		n++
	}
	// Ownership remediations reference service users (e.g. syslog) that may be absent —
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
	// /etc/systemd/journald.conf.d) — create parents first or the file resource aborts the run.
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
		if v, ok := fa["verify"]; ok { // e.g. visudo -cf %{path} — never ship an invalid file
			_, _ = fmt.Fprintf(&b, "  verify '%s'\n", v)
		}
		if !hasContent { // pure owner/perm fix: the `file` resource fails on a DIRECTORY or a
			// missing path (cross-OS noise like /var/log/apt). Guard so it SKIPS instead of
			// aborting the whole run; a real file gets fixed, anything else is left alone.
			_, _ = fmt.Fprintf(&b, "  only_if { ::File.file?(%q) }\n", path)
		}
		b.WriteString("end\n\n")
		if !hasContent { // the path may be a DIRECTORY (e.g. /var/log/apt) — the file resource
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
		// runtime uid — they check file ownership, which $FileOwner/$FileGroup already satisfy.
		// The old privdrop drop-in is removed so it can't keep bricking rsyslog on re-apply.
		b.WriteString("file '/etc/rsyslog.d/00-pavois-privdrop.conf' do\n  action :delete\n" +
			"  notifies :restart, 'service[rsyslog]', :delayed\n" +
			"  only_if { ::File.exist?('/etc/rsyslog.d/00-pavois-privdrop.conf') }\nend\n\n")
		b.WriteString("file \"/etc/rsyslog.d/00-pavois-log-ownership.conf\" do\n" +
			"  content \"# pavois: own logs as syslog:adm (no privilege drop — breaks rsyslog on Trixie)\\n" +
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
	// key=value drop-ins (pwquality, faillock): one file per config, all keys merged.
	// Their parent .d dir may not exist (e.g. /etc/security/faillock.conf.d) and `file`
	// won't create parents — emit a recursive `directory` first, deduped.
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
			content.WriteString(k + " = " + keyvals[f][k] + "\\n")
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
	// already exists and never reorder existing lines — we add ours ahead of `before`.
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
	// (no lockout) and reloaded (not restarted, keeps existing sessions).
	if len(sshd) > 0 {
		var content strings.Builder
		for _, k := range sortedKeysS(sshd) {
			content.WriteString(k + " " + sshd[k] + "\\n")
		}
		_, _ = fmt.Fprintf(&b, "file %q do\n  content \"%s\"\n  verify 'sshd -t -f %%{path}'\n  notifies :reload, 'service[ssh]'\nend\n\n",
			"/etc/ssh/sshd_config.d/99-pavois.conf", content.String())
		b.WriteString("service 'ssh' do\n  action :nothing\nend\n\n")
		n += len(sshd)
	}
	if auditRuleset && auditRules != "" { // Pavois audit ruleset -> one file
		// mode 0640: audit rules must not be group/other-readable (fileperm-etc-audit-rulesd
		// checks `find -perm /0137`); a default 0644 file is world-readable and fails it.
		_, _ = fmt.Fprintf(&b, "file %q do\n  content %q\n  mode '0640'\nend\n\n",
			"/etc/audit/rules.d/99-pavois.rules", auditRules)
		// Deploying the file is not enough: the rules only auto-load at the NEXT boot, so without
		// this every audit control fails until a reboot. Load now with augenrules. The ruleset ends
		// with `-e 2` (immutable) — once loaded you can't reload until reboot, so skip if already
		// immutable (auditctl -s shows enabled 2). Full paths: augenrules/auditctl live in /sbin.
		b.WriteString("execute 'pavois-audit-load' do\n" +
			"  command '/sbin/augenrules --load 2>/dev/null || augenrules --load'\n" +
			"  not_if 'auditctl -s 2>/dev/null | grep -qE \"^enabled 2\"'\nend\n\n")
		// syscall auditing is INERT without audit=1 on the kernel cmdline (revealed by the
		// behavioral probe) — fold it into the cmdline drop-in emitted below.
		cmdline["audit=1"] = true
		cmdline["audit_backlog_limit=8192"] = true
		n++
	}
	// All kernel cmdline params (audit + the R8 mitigations: spectre_v2, l1tf, mds…) go into
	// ONE grub drop-in that APPENDS to GRUB_CMDLINE_LINUX, then regenerate grub.cfg (no native
	// grub resource -> execute). Reboot needed to take effect.
	if len(cmdline) > 0 {
		// Debian's /etc/default/grub does NOT source /etc/default/grub.d/ (that's an Ubuntu
		// convention, and it varies between Debian images) — so our drop-in would be silently
		// ignored. Guarantee the sourcing first, or the cmdline mitigations never reach grub.cfg.
		b.WriteString("execute 'pavois-grub-source-dropins' do\n" +
			`  command 'printf "\nif [ -d /etc/default/grub.d ]; then for x in /etc/default/grub.d/*.cfg; do [ -e \"\$x\" ] && . \"\$x\"; done; fi\n" >> /etc/default/grub'` +
			"\n  not_if 'grep -q /etc/default/grub.d /etc/default/grub'\nend\n\n")
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
		content := "GRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE_LINUX " + strings.Join(safe, " ") + "\"\n"
		if iommuForce {
			content += "systemd-detect-virt -q -v || GRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE_LINUX iommu=force\"\n"
		}
		_, _ = fmt.Fprintf(&b, "file %q do\n  content %q\n  notifies :run, 'execute[update-grub]', :immediately\nend\n\n",
			"/etc/default/grub.d/99-pavois-cmdline.cfg", content)
		b.WriteString("execute 'update-grub' do\n  command 'update-grub'\n  action :nothing\nend\n\n")
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
					"# Interim ONLY (review, and verify boot in a SECOND session first) — a bind mount with nofail:\n"+
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
		// A proper /etc/grub.d/ SCRIPT (shebang + heredoc) so update-grub EMITS the directives
		// into grub.cfg; it reads the salted hash from a sibling dotfile (ignored by update-grub).
		_, _ = fmt.Fprintf(&b, "file '/etc/grub.d/40_pavois_password' do\n  content %q\n  mode '0755'\nend\n\n",
			"#!/bin/sh\ncat <<EOF\nset superusers=\"root\"\npassword_pbkdf2 root $(cat /etc/grub.d/.pavois-grub-hash)\nEOF\n")
		b.WriteString(`execute 'pavois-grub-password' do
  command 'H=$(printf "%s\n%s\n" "$(cat /tmp/pavois-grub-pw)" "$(cat /tmp/pavois-grub-pw)" | grub-mkpasswd-pbkdf2 2>/dev/null | grep -oE "grub\.pbkdf2\.[^ ]+"); [ -n "$H" ] && { printf "%s\n" "$H" > /etc/grub.d/.pavois-grub-hash; chmod 0600 /etc/grub.d/.pavois-grub-hash; grep -q -- "--unrestricted" /etc/grub.d/10_linux || sed -ri "/^CLASS=/ s/\"\$/ --unrestricted\"/" /etc/grub.d/10_linux; /usr/sbin/update-grub; }; rm -f /tmp/pavois-grub-pw'
  not_if 'test -s /etc/grub.d/.pavois-grub-hash'
end

`)
		reboot = true
		n++
	}
	if faillockWanted {
		// pam_faillock via DIRECT common-* edits, NOT pam-auth-update: our pwhistory edit already
		// counts as a "local modification" so pam-auth-update refuses common-* without --force, and
		// --force would drop our pwhistory line. We add only the preauth line (before pam_unix) and
		// the account line — neither shifts the post-pam_unix jump offsets (success=N), so the auth
		// stack stays correct; audit + even_deny_root satisfy the controls. SSH key auth bypasses
		// the password stack, so a slip here can't lock out key login.
		fl := "audit silent deny=5 unlock_time=900 even_deny_root"
		_, _ = fmt.Fprintf(&b, "execute 'pavois-faillock-preauth' do\n  command 'sed -ri \"/^auth.*pam_unix\\.so/i auth required pam_faillock.so preauth %s\" /etc/pam.d/common-auth'\n  only_if 'test -f /etc/pam.d/common-auth'\n  not_if 'grep -qE \"pam_faillock.so\" /etc/pam.d/common-auth'\nend\n\n", fl)
		b.WriteString("execute 'pavois-faillock-account' do\n  command 'printf \"account required pam_faillock.so\\n\" >> /etc/pam.d/common-account'\n  only_if 'test -f /etc/pam.d/common-account'\n  not_if 'grep -qE \"pam_faillock.so\" /etc/pam.d/common-account'\nend\n\n")
		n++
	}
	if dconfWanted {
		// GNOME dconf hardening, full CIS pattern: a keyfile (the settings) AND a locks file (so
		// users can't override them) under /etc/dconf/db/local.d, then `dconf update` to compile
		// the binary db. The checks grep BOTH the .d keyfile and the locks/ file, hence both.
		keyfile := "[org/gnome/login-screen]\nbanner-message-enable=true\n" +
			"banner-message-text='Authorized access only. All activity is monitored and recorded.'\n" +
			"disable-user-list=true\n\n[org/gnome/desktop/media-handling]\nautomount=false\n" +
			"automount-open=false\nautorun-never=true\n\n[org/gnome/desktop/screensaver]\n" +
			"lock-enabled=true\nlock-delay=uint32 5\n\n[org/gnome/desktop/session]\nidle-delay=uint32 900\n"
		locks := "/org/gnome/login-screen/banner-message-enable\n/org/gnome/login-screen/banner-message-text\n" +
			"/org/gnome/login-screen/disable-user-list\n/org/gnome/desktop/media-handling/automount\n" +
			"/org/gnome/desktop/media-handling/automount-open\n/org/gnome/desktop/media-handling/autorun-never\n" +
			"/org/gnome/desktop/screensaver/lock-enabled\n/org/gnome/desktop/screensaver/lock-delay\n" +
			"/org/gnome/desktop/session/idle-delay\n"
		b.WriteString("directory '/etc/dconf/db/local.d/locks' do\n  recursive true\nend\n\n")
		_, _ = fmt.Fprintf(&b, "file '/etc/dconf/db/local.d/00-pavois-hardening' do\n  content %q\n  mode '0644'\nend\n\n", keyfile)
		_, _ = fmt.Fprintf(&b, "file '/etc/dconf/db/local.d/locks/00-pavois-locks' do\n  content %q\n  mode '0644'\nend\n\n", locks)
		b.WriteString("execute 'pavois-dconf-update' do\n  command 'dconf update 2>/dev/null || true'\nend\n\n")
		n++
	}
	if kernelBuildWanted {
		// kconfig hardening can't be done at runtime — it needs a kernel built with the KSPP
		// options. Pavois DELIVERS the recipe (it does NOT run it: ~20GB disk, 30-60min, reboot,
		// the admin's call). The script bases on the running kernel's config and merges the options
		// Pavois's kconfig controls require. ARM64-only / removed options are filtered by the
		// controls' only_if guards, so they're never targeted here.
		script := "#!/bin/sh\n" + `# Pavois — build a KSPP-hardened kernel. HEAVY: ~20GB free disk, 30-60min, then reboot.
# Review before running. Run as root on a host with enough resources (NOT auto-run by Pavois).
set -e
KVER=$(uname -r)
echo "==> build dependencies"
apt-get update
apt-get install -y build-essential fakeroot dpkg-dev libncurses-dev bison flex libssl-dev libelf-dev bc dwarves rsync kmod cpio lz4 zstd lzop xz-utils
GCCV=$(gcc -dumpversion | cut -d. -f1)
apt-get install -y "gcc-${GCCV}-plugin-dev" || apt-get install -y gcc-plugin-dev || true
echo "==> kernel source matching the RUNNING kernel (needs deb-src enabled)"
cd /usr/src
SRCVER=$(dpkg-query -W -f='${source:Version}' "linux-image-$KVER" 2>/dev/null || true)
CODENAME=$(. /etc/os-release 2>/dev/null; echo "$VERSION_CODENAME")
# pin to the running kernel's source version, else this release's current point release, else latest
apt-get source "linux=$SRCVER" 2>/dev/null || apt-get source "linux/$CODENAME" 2>/dev/null || apt-get source linux
SRC=$(find /usr/src -maxdepth 1 -type d -name 'linux-*' | sort | tail -1)
cd "$SRC"
cp "/boot/config-$KVER" .config
echo "==> applying Pavois KSPP options"
for o in DEBUG_CREDENTIALS DEBUG_NOTIFIERS DEBUG_SG PAGE_POISONING PAGE_POISONING_NO_SANITY PAGE_POISONING_ZERO PANIC_ON_OOPS MODULE_SIG MODULE_SIG_ALL MODULE_SIG_FORCE MODULE_SIG_SHA512 GCC_PLUGINS GCC_PLUGIN_LATENT_ENTROPY GCC_PLUGIN_RANDSTRUCT GCC_PLUGIN_STACKLEAK GCC_PLUGIN_STRUCTLEAK GCC_PLUGIN_STRUCTLEAK_BYREF_ALL; do
  scripts/config --enable "CONFIG_$o"
done
for o in DEBUG_FS HIBERNATION IA32_EMULATION KEXEC MODIFY_LDT_SYSCALL PROC_KCORE SLAB_MERGE_DEFAULT X86_VSYSCALL_EMULATION DEBUG_INFO; do
  scripts/config --disable "CONFIG_$o"
done
scripts/config --disable SYSTEM_TRUSTED_KEYS --disable SYSTEM_REVOCATION_KEYS
make olddefconfig
echo "==> building (long)"; make -j"$(nproc)" bindeb-pkg
echo "==> installing"; dpkg -i ../linux-image-*.deb
update-grub
echo "==> DONE — reboot into the hardened kernel, then re-scan with Pavois."
`
		_, _ = fmt.Fprintf(&b, "file '/usr/local/sbin/pavois-harden-kernel.sh' do\n  content %q\n  owner 'root'\n  group 'root'\n  mode '0750'\nend\n\n", script)
		b.WriteString("log 'Pavois: KSPP kernel-build recipe DELIVERED at /usr/local/sbin/pavois-harden-kernel.sh — review and run it manually (heavy: ~20GB disk, 30-60min, reboot). Pavois does not run it for you; kconfig controls pass once you boot the rebuilt kernel.' do\n  level :warn\nend\n\n")
		n++
	}
	if len(manualFixes) > 0 {
		// Deliver (never run) the fixes that need judgement or are operationally risky, as one
		// reviewable script — same contract as the kernel-build recipe above.
		sort.Slice(manualFixes, func(i, j int) bool { return manualFixes[i].id < manualFixes[j].id })
		var sb strings.Builder
		sb.WriteString("#!/bin/sh\n")
		sb.WriteString("# Pavois — MANUAL hardening fixes. Pavois does NOT run these: each needs human\n")
		sb.WriteString("# judgement or is operationally risky. Review EACH block, then run the ones you want.\n\n")
		for _, mf := range manualFixes {
			sb.WriteString("# === " + mf.id + " ===\n")
			if mf.reason != "" {
				sb.WriteString("# " + mf.reason + "\n")
			}
			sb.WriteString(strings.TrimRight(mf.command, "\n") + "\n\n")
		}
		_, _ = fmt.Fprintf(&b, "file '/usr/local/sbin/pavois-manual-fixes.sh' do\n  content %q\n  owner 'root'\n  group 'root'\n  mode '0750'\nend\n\n", sb.String())
		_, _ = fmt.Fprintf(&b, "log 'Pavois: %d MANUAL fix(es) DELIVERED at /usr/local/sbin/pavois-manual-fixes.sh — review and run them yourself; Pavois will not (they need judgement or are risky).' do\n  level :warn\nend\n\n", len(manualFixes))
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
// `Defaults requiretty` (ANSSI BP-028 R39) — Pavois can apply that control, so its own
// management path must survive it. Used for the sudo cinc-apply runs (not scp).
func sshTTY(target, cmd string) []string {
	return append(append(append([]string{"-tt"}, sshOpts()...), target), cmd)
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
	out := cmd.OutOrStdout()

	// Danger gate: an enabled remediation flagged `danger:` can brick or lock out the
	// host. Refuse to converge it unless the operator acknowledged the risk — either
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
		_, _ = fmt.Fprintln(out, "pavois: ✗ refusing to apply — dangerous remediation(s) not acknowledged:")
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
			"(sshd/sysctl/cmdline/keyval). Those drop-ins are rewritten in full — applying a SUBSET "+
			"plan wipes the sibling controls not listed here (e.g. re-enables root SSH, drops sysctls). "+
			"Apply the FULL `harden plan` output, or use `scan --controls` to test one control.\n", len(p.Rules))
	}
	// If a grub_password remediation is enabled, generate a strong secret and store it in a
	// local 0600 vault BEFORE compiling — the recipe sets the (salted) hash on the target.
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
	recipe, count, reboot, pending, conflicts := compileRecipe(p, string(auditRules), grubPassword, haStandard)
	if len(conflicts) > 0 {
		_, _ = fmt.Fprintln(out, "pavois: ✗ conflicting remediations — refusing to apply:")
		for _, c := range conflicts {
			_, _ = fmt.Fprintf(out, "    - %s\n", c)
		}
		return fmt.Errorf("%d remediation conflict(s); resolve them in the plan (disable one side, or set a choice) and retry", len(conflicts))
	}
	if pending > 0 {
		_, _ = fmt.Fprintf(out, "pavois: ⚠ %d enabled rule(s) have no remediation yet (pending) — they are skipped, nothing is generated for them.\n", pending)
	}
	_, _ = fmt.Fprintf(out, "pavois: compiled %d enabled item(s) into native Chef resources:\n\n%s\n", count, recipe)
	if reboot {
		if haReboot {
			// Reboot is a Chef action, not an out-of-band step. NB: the `reboot` resource's
			// :reboot_now is a no-op under cinc-apply (chef-apply doesn't run the reboot
			// handler a full chef-client run would), so issue it with an `execute` LAST —
			// every change applies first, then the box reboots in-run (activates audit=1).
			recipe += "# pavois: reboot in-run to activate kernel cmdline (audit=1) / modules / sysctl\n" +
				"execute 'pavois-reboot' do\n  command 'systemctl reboot'\nend\n"
			_, _ = fmt.Fprintln(out, "pavois: ⚠ changes need a REBOOT — Pavois will reboot the target via Chef at the end of the run.")
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
	// capture runs a read-only command on the target over raw ssh and returns its trimmed
	// stdout (used for the reboot proof: boot_id is world-readable, no sudo needed).
	capture := func(remote string) string {
		c := exec.Command("ssh", append(append(sshOpts(), target), remote)...) //nolint:gosec // fixed args, operator target
		o, _ := c.Output()
		return strings.TrimSpace(string(o))
	}
	_, _ = fmt.Fprintf(os.Stderr, "pavois: ensuring cinc-client on %s…\n", target)
	ensure := "command -v cinc-apply >/dev/null || curl -L https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc"
	if err := run("ssh", sshTTY(target, ensure)...); err != nil {
		return fmt.Errorf("install cinc-client: %w", err)
	}
	_, _ = fmt.Fprintln(os.Stderr, "pavois: copying recipe…")
	if err := run("scp", append(append(sshOpts(), tmp.Name()), target+":/tmp/pavois-harden.rb")...); err != nil {
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
	// (a no-op when clean), so we run it only when `dpkg --audit` reports a broken state — and say
	// so, instead of surfacing the cryptic exit-100 stacktrace later.
	if capture("command -v dpkg >/dev/null 2>&1 && dpkg --audit 2>/dev/null | grep -q . && echo broken") == "broken" {
		_, _ = fmt.Fprintln(os.Stderr, "pavois: dpkg is in an interrupted state (a prior install was cut short) — repairing with 'dpkg --configure -a' before continuing…")
		if err := run("ssh", sshTTY(target, "sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a")...); err != nil {
			return fmt.Errorf("dpkg is interrupted on %s and auto-repair failed; run 'sudo dpkg --configure -a' on the target, then retry: %w", target, err)
		}
	}

	_, _ = fmt.Fprintln(os.Stderr, "pavois: refreshing apt cache…")
	_ = run("ssh", sshTTY(target, "if command -v apt-get >/dev/null 2>&1; then sudo env APT_LISTBUGS_FRONTEND=none apt-get update -qq || true; fi")...)

	// Terraform-style: show the REAL diff (why-run changes nothing) before asking.
	_, _ = fmt.Fprintf(out, "\npavois: planned changes on %s (nothing applied yet):\n\n", target)
	// APT_LISTBUGS_FRONTEND=none: if apt-listbugs is (being) installed, its apt hook otherwise
	// ABORTS every non-interactive apt operation in the converge (it can't prompt), which makes
	// the other package installs fail. Setting it none makes apt-listbugs a no-op for THIS
	// converge only; a normal admin `apt install` later still gets its critical-bug warnings.
	why := "sudo env CHEF_LICENSE=accept-silent APT_LISTBUGS_FRONTEND=none cinc-apply /tmp/pavois-harden.rb --why-run"
	if err := run("ssh", sshTTY(target, why)...); err != nil {
		return fmt.Errorf("why-run: %w", err)
	}

	if !haYes {
		_, _ = fmt.Fprint(out, "\nApply these changes? [y/N]: ")
		ans, _ := bufio.NewReader(os.Stdin).ReadString('\n')
		if a := strings.ToLower(strings.TrimSpace(ans)); a != "y" && a != "yes" {
			_, _ = fmt.Fprintln(out, "pavois: aborted — nothing applied.")
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
	conv := "sudo env CHEF_LICENSE=accept-silent APT_LISTBUGS_FRONTEND=none cinc-apply /tmp/pavois-harden.rb"
	if err := run("ssh", sshTTY(target, conv)...); err != nil {
		// With --reboot the run ends by rebooting the box: the SSH session drops mid-run,
		// which surfaces as a non-zero exit. That's expected — wait for the box to return.
		if !reboot || !haReboot {
			return fmt.Errorf("converge: %w", err)
		}
	}
	if reboot && haReboot {
		// Like Ansible's reboot module (wait_for_connection): wait for the connection to
		// DROP (box going down), then for it to come back — a plain re-ping right away
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

	// --scan: close the loop — re-scan, fresh report, new grade.
	root := findRoot()
	machine, transport := machineTransport(target)
	_ = os.MkdirAll(filepath.Join(root, "reports"), 0o750)
	jsonPath := filepath.Join(root, "reports", fmt.Sprintf("rapport-%s-%s-%s.json",
		slug(machine), strings.TrimSuffix(transport, "://"), time.Now().Format("20060102-150405")))
	_, _ = fmt.Fprintln(os.Stderr, "Pavois: re-scanning…")
	if _, err := engine.Run(engine.Options{
		Root: root, Target: target, Profile: "linux/" + p.OS, Engine: "auto",
		Key: haKey, Sudo: true, JSONOut: jsonPath,
		// re-scan ON the target for ssh (like harden plan): a real pty so sudo works under
		// Defaults use_pty, and raw ssh that uses ~/.ssh defaults instead of failing when no
		// --key/agent key reaches cinc's train-ssh transport.
		OnTarget: strings.Contains(target, "@"),
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
		writeScorecard(out, letter, pts, res.Passed, res.Total, res.Qualified)
	}

	// Validate every applied remediation actually made its control PASS — a remediation
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
		// When a real reboot happened, the re-scan ran AFTER it — so a PASS is reboot-proven
		// (the change survived the reboot), not just live. That's the empirical persistence proof.
		proven := ""
		if reboot && haReboot {
			proven = " — re-scanned after a real reboot, so these passes are reboot-proven"
		}
		_, _ = fmt.Fprintf(out, "\npavois: remediation check — %d/%d applied controls now PASS%s.\n", passed, applied, proven)
		if len(failed) > 0 {
			sort.Strings(failed)
			_, _ = fmt.Fprintf(out, "pavois: ⚠ %d did NOT pass (broken remediation, or needs reboot/config — investigate):\n", len(failed))
			for _, c := range failed {
				_, _ = fmt.Fprintf(out, "    - %s\n", c)
			}
		}
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
		_, _ = fmt.Fprintf(out, "pavois: reboot proof written (boot_id unchanged — verify) → %s\n", path)
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
	body := fmt.Sprintf("# Pavois %s secret for %s — keep safe, Pavois cannot recover it.\n%s\n", kind, target, secret)
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		return "", err
	}
	return path, nil
}
