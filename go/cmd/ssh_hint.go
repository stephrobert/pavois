package cmd

import (
	"os"
	"strings"
)

// What to say when an SSH target does not answer.
//
// Issue #285: the hint always advised passing --key, including when --key had just been passed on
// the command line. The reporter's actual cause was on the target, and the target knew it:
//
//	sshd[1314]: Authentication refused: bad ownership or modes for file /root/.ssh/authorized_keys
//
// The advice was good advice in general and wrong there, and being wrong it sent the reader back to
// their own command line instead of to the machine that was refusing them. "No key was offered" and
// "the key was offered and refused" are two different failures; one message cannot serve both.
//
// So the hint is chosen from what we know: whether a key was supplied, and whether an agent could
// have supplied one.

// sshFailureHint returns the advice lines for a target that could not be reached, given the key the
// user passed (empty when none). The leading newline is included so callers can append it directly.
func sshFailureHint(key string) string {
	if key == "" && os.Getenv("SSH_AUTH_SOCK") == "" {
		// Nothing could have authenticated: no key, no agent. This is the case the original
		// message was written for, and it is the only one where --key is the answer.
		return "\n  a host that answers `ssh <target>` can still fail here: the engine does not fall back\n" +
			"  to ~/.ssh/id_ed25519 the way the ssh command does, and no key was passed and no\n" +
			"  ssh-agent is reachable. Pass --key <path>, or add the key to ssh-agent."
	}
	if key == "" {
		return "\n  no --key was passed. An ssh-agent is reachable, so the engine may still have an\n" +
			"  identity to offer; if it does not, pass --key <path> explicitly."
	}
	// A key WAS passed. Do not send the reader back to their own command line: the credential
	// exists, so the interesting question is why the target refused it.
	return "\n  --key was passed, so the key is not what is missing. The engine reached the transport\n" +
		"  and did not get in. Its own message is above, and the usual causes are on the TARGET:\n" +
		"    ownership and mode of ~/.ssh/authorized_keys there (the classic one after a file push:\n" +
		"      it must be owned by that user and not group or world writable),\n" +
		"    the account exists but this key is not in its authorized_keys,\n" +
		"    sshd refuses the user (AllowUsers, PermitRootLogin) or the host is unreachable.\n" +
		"  `ssh -i <key> -v <target>` on this machine will say which."
}

// withTarget substitutes the literal <target> placeholder so the hint can name the host.
func withTarget(hint, target string) string {
	return strings.ReplaceAll(hint, "<target>", target)
}
