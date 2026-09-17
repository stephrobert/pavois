package cmd

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Issue #200: `harden apply` invoked ssh and scp unconditionally, so a local target meant
// `ssh -tt local …`, an attempt to reach a host literally named "local". `pavois scan local` worked
// and `pavois harden apply local` could not, on the one target every user tries first.
//
// The hazard was worse than a clean failure: an operator with a `Host local` entry in their
// ~/.ssh/config would have been sent to an arbitrary machine rather than told no.
//
// These tests pin the transport choice itself, which is cheap and deterministic. Whether a converge
// succeeds is the VM scenario's job (tools/release/scenario.sh runs both transports).

func TestHostShellPicksLocalForALocalTarget(t *testing.T) {
	h := newHostShell("local", "")
	if !h.local {
		t.Fatal("newHostShell(\"local\") is not local: harden apply would ssh to a host named \"local\"")
	}
	c := h.cmd("true")
	if filepath.Base(c.Path) == "ssh" {
		t.Errorf("a local target still runs through ssh: %v", c.Args)
	}
	if got := strings.Join(c.Args, " "); !strings.Contains(got, "true") {
		t.Errorf("the command was not passed through: %q", got)
	}
}

func TestHostShellStillUsesSSHForARemoteTarget(t *testing.T) {
	h := newHostShell("pavois@203.0.113.7", "/dev/null")
	if h.local {
		t.Fatal("a user@host target was taken for local")
	}
	args := strings.Join(h.cmd("true").Args, " ")
	for _, want := range []string{"ssh", "pavois@203.0.113.7", "true"} {
		if !strings.Contains(args, want) {
			t.Errorf("remote command is missing %q: %s", want, args)
		}
	}
	// -F /dev/null is not decoration: a global `Host *` ProxyJump breaks direct connections with a
	// misleading "UNKNOWN port 65535" that reads exactly like a broken target.
	if !strings.Contains(args, "-F /dev/null") {
		t.Errorf("the global ssh_config is not neutralised: %s", args)
	}
}

// A pty is negotiated only where there is one to negotiate. Locally sudo already has the operator's
// terminal, and the remote `IFS= read -r __P` dance would hang: with no password on a -tt pty,
// closing stdin never becomes an EOF, so the read waits for a line that never comes.
func TestHostShellDoesNotAllocateAPtyLocally(t *testing.T) {
	args := strings.Join(newHostShell("local", "").tty("id", "").Args, " ")
	if strings.Contains(args, "-tt") {
		t.Errorf("a local command asked for a pty: %s", args)
	}
	if strings.Contains(args, "read -r __P") {
		t.Errorf("a local command carries the remote password dance: %s", args)
	}
	remote := strings.Join(newHostShell("pavois@host", "").tty("id", "secret").Args, " ")
	if !strings.Contains(remote, "-tt") {
		t.Errorf("a remote sudo command has no pty, which breaks Defaults requiretty: %s", remote)
	}
	if strings.Contains(remote, "secret") {
		t.Errorf("the sudo password reached argv, where ps can read it: %s", remote)
	}
}

// push and fetch are a copy when both ends are this machine. Anything else would shell out to scp
// against a host that does not exist.
func TestHostShellCopiesLocallyInsteadOfScp(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "recipe.rb")
	if err := os.WriteFile(src, []byte("package 'nothing'\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	h := newHostShell("local", "")

	dst := filepath.Join(dir, "pushed.rb")
	if err := h.push(src, dst); err != nil {
		t.Fatalf("push on a local target: %v", err)
	}
	back := filepath.Join(dir, "fetched.rb")
	if err := h.fetch(dst, back); err != nil {
		t.Fatalf("fetch on a local target: %v", err)
	}
	got, err := os.ReadFile(back) //nolint:gosec // a path this test just wrote
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "package 'nothing'\n" {
		t.Errorf("the file did not survive the round trip: %q", got)
	}
}

// The reboot wait loop asks whether the target answers. Locally it always does, and it must not
// spend four minutes discovering that this machine has not gone away.
func TestHostShellIsAlwaysReachableLocally(t *testing.T) {
	if !newHostShell("local", "").reachable() {
		t.Error("a local target reported itself unreachable")
	}
}
