package cmd

import (
	"fmt"
	"os"

	"golang.org/x/term"
)

// promptSecret reads a secret from the controlling terminal (/dev/tty) with echo
// DISABLED, so it never appears on screen, in argv, or in the shell history. The
// value lives only in memory and is handed to cinc-auditor over stdin (--config -).
func promptSecret(label string) (string, error) {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		// no controlling tty (e.g. a pipe) — fall back to stdin, still no echo.
		fmt.Fprint(os.Stderr, label)
		b, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		return string(b), err
	}
	defer tty.Close()
	fmt.Fprint(tty, label)
	b, err := term.ReadPassword(int(tty.Fd()))
	fmt.Fprintln(tty)
	return string(b), err
}

// resolveSudoPass returns the sudo password from, in order: an interactive no-echo
// prompt (--sudo-prompt), then the PAVOIS_SUDO_PASSWORD env var (for CI). It NEVER
// accepts an inline CLI value — that would leak via `ps` and the shell history.
func resolveSudoPass(prompt bool) (string, error) {
	if prompt {
		return promptSecret("[sudo] password for the target: ")
	}
	v := os.Getenv("PAVOIS_SUDO_PASSWORD")
	os.Unsetenv("PAVOIS_SUDO_PASSWORD") // drop from our env so no child process inherits it
	return v, nil
}

// resolveSSHPass mirrors resolveSudoPass for the SSH login password: --ssh-prompt
// (no-echo) or PAVOIS_SSH_PASSWORD, falling back to a (discouraged) inline value.
func resolveSSHPass(inline string, prompt bool) (string, error) {
	if prompt {
		return promptSecret("SSH password for the target: ")
	}
	if v := os.Getenv("PAVOIS_SSH_PASSWORD"); v != "" {
		os.Unsetenv("PAVOIS_SSH_PASSWORD") // drop from our env so no child process inherits it
		return v, nil
	}
	return inline, nil
}
