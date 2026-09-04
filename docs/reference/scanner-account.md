# The pavois scanner account (least-privilege, no NOPASSWD)

pavois needs root on the target to read the **effective** configuration
(`sshd -T`, `sysctl`, `systemctl show`, `auditctl`, `getenforce`,
`authselect current`, `nginx -T`, …) and to run a Chef converge for
`harden apply`. This guide creates a dedicated scanner account that gets that
access through an **authenticated** sudo: not `NOPASSWD: ALL`: so the target
passes pavois's own `sudo-require-authentication` control instead of being
weakened by the tool that audits it.

## Why not a command allowlist?

A per-command sudoers allowlist looks tighter, but pavois reads protected files
via `grep`/`find`/`awk`/`stat`, which are [GTFOBins](https://gtfobins.github.io/)
(`find … -exec /bin/sh`, `awk 'BEGIN{system("/bin/sh")}'`). Allowing those as
root *is* a root shell, so the allowlist is false security. The controls pavois
ships (and CIS/ANSSI ask for) put the real control on **authentication + audit
logging**, which is also how comparable tools run:

| Tool | Privileged-account posture |
| --- | --- |
| Ansible | `become` **password** (`--ask-become-pass`, Vault in CI); command restriction is documented as "problematic" |
| Chef `knife bootstrap` | `--sudo --ask-sudo-pass` (password, not NOPASSWD) |
| Tenable/Nessus | credentialed account with escalation; "Attempt Least Privilege" builds a sudoers allowlist iteratively, but full config/file-permission checks still **require root** |
| Lynis / OpenSCAP | run **as root** directly |

## 1. Create the account

```bash
# on the target, as root
useradd --create-home --shell /bin/bash pavois

# SSH key-only login (no password login): install your public key
install -d -m 0700 -o pavois -g pavois /home/pavois/.ssh
printf '%s\n' "ssh-ed25519 AAAA... you@host" > /home/pavois/.ssh/authorized_keys
chown pavois:pavois /home/pavois/.ssh/authorized_keys
chmod 0600 /home/pavois/.ssh/authorized_keys

# set a sudo PASSWORD (you type it at scan time; it is never stored on the target)
passwd pavois
```

## 2. Install the sudoers drop-in

Use [`pavois-scanner-sudoers.example`](./pavois-scanner-sudoers.example):

```bash
sudo install -m 0440 pavois-scanner-sudoers.example /etc/sudoers.d/pavois
sudo visudo -cf /etc/sudoers.d/pavois     # must say: parsed OK
```

It grants `pavois ALL=(ALL) ALL` (authenticated sudo), plus `!requiretty` (sudo
works from the non-interactive scan), `!noexec` (cinc execs programs), and a
dedicated `logfile`.

**Remove any `NOPASSWD` line for the account.** Cloud images often ship one in
`/etc/sudoers.d/90-cloud-init-users`; `sudo-require-authentication` greps for
`NOPASSWD`, so it must be gone, not just overridden:

```bash
sudo sed -ri 's/^(pavois .*NOPASSWD.*)$/# \1/' /etc/sudoers.d/90-cloud-init-users
```

### cloud-init

Provision the account without NOPASSWD from the start:

```yaml
users:
  - name: pavois
    shell: /bin/bash
    lock_passwd: false          # allow the sudo password
    ssh_authorized_keys:
      - ssh-ed25519 AAAA... you@host
    sudo: "ALL=(ALL) ALL"       # NOT "ALL=(ALL) NOPASSWD:ALL"
```

## 3. Run pavois: enter the password at the command

Pass the sudo password over stdin with `--sudo-prompt` (no echo, never in argv or
shell history):

```bash
bin/pavois scan pavois@host --profile linux/rhel8 --sudo-prompt --key ~/.ssh/id_ed25519
# [sudo] password for the target: ‹typed, not echoed›
```

For CI, set `PAVOIS_SUDO_PASSWORD` in the environment instead (pavois reads it,
then unsets it so no child process inherits it):

```bash
PAVOIS_SUDO_PASSWORD="$SUDO_PW" bin/pavois scan pavois@host --profile linux/rhel8 --sudo --key ~/.ssh/id_ed25519
```

## Transport note (sudo vs root)

- **Native SSH** (default, `--sudo` / `--sudo-prompt`): cinc runs each probe as
  `sudo <cmd>` over SSH. This works with the password account today. As Tenable
  documents, a per-command `sudo` environment (`env_reset`, `secure_path`) does
  not always match a full root environment, so a few checks can read differently
  than under root.
- **On-target** (`--on-target`, recommended): pavois runs cinc *as root on the
  target* for a root-equivalent result. It supports the password account: the
  sudo password is fed to the remote `sudo -S` over stdin (never argv). This is
  the accurate path: on a hardened AlmaLinux 8 it scores the same grade as a
  NOPASSWD root run, ~40 controls higher than native-SSH per-command sudo, while
  still passing `sudo-require-authentication`. Prefer it with the password
  account:

  ```bash
  bin/pavois scan pavois@host --profile linux/rhel8 --sudo-prompt --on-target --key ~/.ssh/id_ed25519
  ```
