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
				`"$d/.probe" 2>/dev/null; rc=$?; rm -f "$d/.probe"; `+
				`[ "$rc" = 0 ] && printf '%%s' "$d"`, cand)
		if sudo != "" && strings.HasPrefix(cand, "/opt") {
			// /opt is root-owned on every supported system; the rest are reachable as the user.
			probe = sudo + "sh -c '" + strings.ReplaceAll(probe, "'", `'\''`) + "'"
		}
		out, err := ssh(probe)
		if dir := strings.TrimSpace(out); err == nil && dir != "" {
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
