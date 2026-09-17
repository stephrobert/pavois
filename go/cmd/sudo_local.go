package cmd

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
)

// `--sudo` on a LOCAL target, which is the first command every entry point recommends.
//
// Issue #281: `pavois scan local --sudo` is printed by `pavois doctor` itself, it is the featured
// command on www.pavois.dev, it is in the README, and it did not work. CINC refuses it, because a
// local transport cannot elevate:
//
//	Sudo is only valid when running against a remote host. To run this locally with elevated
//	privileges, run the command with `sudo ...`.
//
// The refusal is correct. What was not defensible is that Pavois ASKS FOR THE SAME THING a few
// lines earlier: scanning unprivileged is refused with "add --sudo (or --sudo-prompt)". Pavois
// recommended a form its own engine rejects, so the contradiction is Pavois's to resolve, not the
// documentation's to work around.
//
// `--sudo` states an intent: run this with the privileges the effective-config reads need. On a
// remote target that is cinc's --sudo. On a local one the only implementation of that intent is to
// re-exec the whole command through sudo, which is exactly what the user would have typed. So that
// is what happens, and it is announced: a hardening tool that escalates silently would be a poor
// advertisement for itself.

// reexecEnv marks the child so a re-exec can never recurse. If sudo somehow returns a non-root
// process, the child refuses rather than spawning another one.
const reexecEnv = "PAVOIS_SUDO_REEXEC"

// reexecUnderSudo re-runs this exact command under sudo when a local target was asked to scan with
// --sudo from an unprivileged account. It returns (handled, error): when handled is true the
// caller must stop, the work has been done by the child.
func reexecUnderSudo(local, wantSudo bool) (bool, error) {
	if !local || !wantSudo || os.Geteuid() == 0 || os.Getenv(reexecEnv) == "1" {
		return false, nil
	}
	exe, err := os.Executable()
	if err != nil {
		return false, fmt.Errorf("--sudo on a local target needs to re-run this command as root, "+
			"and this binary cannot locate itself: %w.\n  run it yourself: sudo pavois %s",
			err, join(os.Args[1:]))
	}
	sudoBin, err := exec.LookPath("sudo")
	if err != nil {
		return false, fmt.Errorf("--sudo cannot elevate a local scan and sudo is not installed.\n" +
			"  a local transport cannot grant itself privileges: run the whole command as root,\n" +
			"  or pass --allow-unprivileged to accept a scan that cannot read the effective config")
	}

	_, _ = fmt.Fprintf(os.Stderr,
		"pavois: --sudo on a local target re-runs this command as root (a local scan cannot elevate itself)\n")

	// The password is NOT piped here. sudo prompts on the terminal, as it would if the user had
	// typed it, and PAVOIS_SUDO_PASSWORD keeps meaning what it means for a REMOTE target. Feeding a
	// stored password to a local root shell is a different act from handing one to a remote sudo,
	// and it is not one this flag was asked to perform.
	args := append([]string{"--", exe}, os.Args[1:]...)
	c := exec.Command(sudoBin, args...) //nolint:gosec // our own executable, our own argv
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	c.Env = append(os.Environ(), reexecEnv+"=1")

	err = c.Run()
	if err == nil {
		return true, nil
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		// The child already said whatever it had to say: exit with its code rather than wrapping a
		// second message around it.
		os.Exit(ee.ExitCode())
	}
	return true, fmt.Errorf("could not re-run under sudo: %w", err)
}

// RestoreOwnership gives the reports back to the user who asked for the scan.
//
// It runs in the CHILD, as root, which is the only process that can. The first version ran it in
// the parent after waiting on the child, and a parent running as the ordinary user cannot chown a
// root-owned file to itself: the call failed silently and the scenario caught it, reporting
// "the reports are owned by root". Only root may give a file away.
//
// Without it, `pavois scan local --sudo` leaves the caller unable to delete their own report.
// sudo sets SUDO_UID and SUDO_GID to the invoking user; if they are absent, this was a real root
// session and there is nobody to give anything back to.
func RestoreOwnership(dir string) {
	if os.Geteuid() != 0 {
		return
	}
	uid, err1 := strconv.Atoi(os.Getenv("SUDO_UID"))
	gid, err2 := strconv.Atoi(os.Getenv("SUDO_GID"))
	if err1 != nil || err2 != nil || uid == 0 {
		return
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		p := filepath.Join(dir, e.Name())
		fi, err := os.Stat(p)
		if err != nil {
			continue
		}
		if st, ok := fi.Sys().(*syscall.Stat_t); ok && int(st.Uid) == uid {
			continue
		}
		_ = os.Chown(p, uid, gid)
	}
	_ = os.Chown(dir, uid, gid)
}

// join renders argv for a message a user can copy.
func join(args []string) string {
	out := ""
	for i, a := range args {
		if i > 0 {
			out += " "
		}
		if a == "" {
			out += `""`
			continue
		}
		needsQuote := false
		for _, r := range a {
			if r == ' ' || r == '\t' || r == '\'' || r == '"' {
				needsQuote = true
				break
			}
		}
		if needsQuote {
			out += strconv.Quote(a)
		} else {
			out += a
		}
	}
	return out
}
