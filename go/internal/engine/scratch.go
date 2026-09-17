package engine

import (
	"fmt"
	"strings"
)

// Where a `--on-target` scan may put the profile it is about to execute.
//
// Issue #288. The answer used to be /tmp, unconditionally. Then Pavois hardens the host,
// `mount-tmp-noexec` applies, and the next `--on-target` scan of that host dies with
// `sh: 1: env: Permission denied` and exit 126: the tool had hardened a machine into a state where
// its own verification could not run, which is precisely the scan an operator performs after
// hardening to prove the result.
//
// Marking that control dangerous was the tempting fix and it would have been the wrong one. It is
// bp28 intermediary and CIS level 1 on nine systems, and it does not brick anything: it breaks one
// transport of one tool. A compliance scanner does not get to weaken a standard for its own
// convenience.
//
// So no directory is assumed. /tmp, /var, /var/tmp and /home ALL have a noexec control in this very
// corpus, so the target is asked which of the candidates can actually execute a file, in order of
// how little they disturb the host.

// scratchCandidates are tried in order. $HOME first because it leaves no trace outside the user's
// own space; /run last among the writable-by-root ones because it is a tmpfs that does not survive
// a reboot, which is fine for the lifetime of a scan and unhelpful for anything else.
var scratchCandidates = []string{
	"$HOME/.pavois-run",
	"/var/tmp/pavois-run",
	"/tmp/pavois-run",
	"/run/pavois-run",
	"/opt/pavois-run",
}

// execDirOnTarget returns a directory on the target that is writable AND executable, creating it.
//
// It does not read /proc/mounts and reason about options: a mount can be noexec through a parent,
// through a bind, or through a container runtime, and every such inference has a case it gets
// wrong. It writes a two-line script and runs it. The answer is the behaviour, not a prediction of
// it.
func execDirOnTarget(ssh func(string) (string, error), sudo string) (string, error) {
	var tried []string
	for _, cand := range scratchCandidates {
		// One round trip per candidate: create it, put a script in it, run the script. `test -x` is
		// NOT enough, because the executable bit is set fine on a noexec mount and the kernel
		// refuses at exec time, which is the whole failure mode here.
		probe := fmt.Sprintf(
			`d=%s; mkdir -p "$d" 2>/dev/null || exit 1; `+
				`printf '#!/bin/sh\necho ok\n' > "$d/.probe" 2>/dev/null || exit 1; `+
				`chmod 0700 "$d/.probe" 2>/dev/null || exit 1; `+
				// >/dev/null, not just 2>/dev/null: the probe script PRINTS, and its "ok" landed on
				// stdout right before the path did. The caller then got "ok\n/home/tester/.pavois-run"
				// and scp was handed a two-line destination, which the remote shell read as a command
				// on line 1 and a path on line 2:
				//   bash: line 2: /home/tester/.pavois-run/profile: No such file or directory
				// The probe's job is its exit code; anything it says belongs nowhere.
				`"$d/.probe" >/dev/null 2>&1; rc=$?; rm -f "$d/.probe"; `+
				`[ "$rc" = 0 ] && printf '%%s' "$d"`, cand)
		if sudo != "" && strings.HasPrefix(cand, "/opt") {
			// /opt is root-owned on every supported system; the rest are reachable as the user.
			probe = sudo + "sh -c '" + strings.ReplaceAll(probe, "'", `'\''`) + "'"
		}
		out, err := ssh(probe)
		// The LAST line, and a path only. A login shell can print a banner, a profile can echo, and
		// any of it would be prepended to the answer: the first version of this shipped a two-line
		// path to scp. A directory never contains a newline, so anything before the last one is
		// noise by definition.
		if dir := lastPath(out); err == nil && dir != "" {
			return dir, nil
		}
		tried = append(tried, cand)
	}
	return "", fmt.Errorf("no directory on the target can execute a file: tried %s.\n"+
		"  every one of them is mounted noexec, which is what `mount-tmp-noexec`, `mount-var-noexec`,\n"+
		"  `mount-var-tmp-noexec` and `mount-home-noexec` do. A --on-target scan copies the profile\n"+
		"  to the target and runs it there, so it needs one executable directory.\n"+
		"  scan over ssh WITHOUT --on-target: slower, and it needs nothing executable on the target",
		strings.Join(tried, ", "))
}

// lastPath returns the last non-empty line of the target's answer, and only if it looks like an
// absolute path. Belt and braces: the shape is checked as well as the position, so a banner ending
// in a word cannot be mistaken for a directory.
func lastPath(out string) string {
	lines := strings.Split(strings.TrimSpace(out), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if s := strings.TrimSpace(lines[i]); strings.HasPrefix(s, "/") {
			return s
		}
	}
	return ""
}

// sudoForbidsExec reports whether sudoers carries a global `Defaults noexec`, which forbids a
// command run through sudo, and everything it spawns, from executing anything.
//
// That is not a directory problem and no working directory fixes it. An effective-configuration
// scan exists to execute commands (`sshd -T`, `sysctl -a`, `systemctl show`), so under this setting
// cinc-auditor is blocked inside mixlib-shellout on its first control. Measured on a clean Ubuntu
// 24.04 against a control group: the same scan runs with noexec off and is blocked with it on,
// whether or not the package managers are carved out.
//
// Pavois cannot work around it, and should not try: the control is doing exactly what it says. What
// it CAN do is stop reporting `exit 126: no report produced`, which names nothing the reader can
// act on, and say what is true.
func sudoForbidsExec(ssh func(string) (string, error)) bool {
	out, err := ssh("sudo -n grep -rhE '^[[:space:]]*Defaults[[:space:]]' /etc/sudoers /etc/sudoers.d/ 2>/dev/null " +
		"| grep -E 'noexec' | grep -cv '!noexec'")
	if err != nil {
		return false // cannot tell: never accuse a target on a failed probe
	}
	n := strings.TrimSpace(out)
	return n != "" && n != "0"
}

// noexecError explains the one thing a reader can act on.
func noexecError(target string) error {
	// The HOST, not the target: `strings.TrimPrefix(target, "root@")` left `pavois@10.0.0.2`
	// untouched and the message then offered `pavois scan root@pavois@10.0.0.2`, a command nobody
	// can run. Caught by the test that reads the message rather than trusting it.
	host := target
	if at := strings.LastIndex(target, "@"); at >= 0 {
		host = target[at+1:]
	}
	return fmt.Errorf("the scan engine cannot run on %s: sudoers carries a global `Defaults noexec`, "+
		"which forbids anything run through sudo from executing another command.\n"+
		"  auditing the EFFECTIVE configuration means running sshd -T, sysctl and systemctl show, so\n"+
		"  the engine is blocked on its first control. No working directory and no elevation trick\n"+
		"  changes that; the setting is doing what it says (ANSSI BP-028 R39, control sudo-noexec).\n"+
		"  scan from a root session instead, where noexec does not apply: pavois scan root@%s --key <path>\n"+
		"  or drop --on-target, which runs the engine here and reaches the target over ssh",
		target, host)
}

// sudoPrefix renders the sudo the caller asked for, if any, in the form the probes use.
func sudoPrefix(o Options) string {
	if !o.Sudo {
		return ""
	}
	if o.SudoPass != "" {
		return "sudo -S " // the password is piped to ssh stdin, never argv
	}
	return "sudo "
}
