# pavois demo: what a fresh Debian 13 server is worth, and what pavois can fix.
#
#   tools/demo/record.sh          (do not run vhs directly: the host is substituted in)
#
# The tape is versioned and the video is a build product of it. That ordering matters: the previous
# demo had no source at all, so nobody could re-record it, fix a typo in it, or tell what it had
# actually run. Every command below really executes against a real Incus VM.
#
# __HOST__ is replaced at record time, so no lab address is ever committed.
#
# Three things learned the hard way while writing this:
#   - use --sudo, not --sudo-prompt: with the prompt, pavois tries the interactive no-echo read
#     FIRST and only falls back to PAVOIS_SUDO_PASSWORD when there is no terminal. VHS provides a
#     real terminal, so the first recording sat on "[sudo] password for the target:" forever.
#   - `harden plan` re-scans by default, and over plain SSH that is ninety seconds of progress bar.
#     `--from` reuses the scan just taken, which is both faster and what an operator would do.
#   - never Type while a command is still running: the text interleaves with its output. Every
#     Sleep below is sized on a measured duration, plus margin.

Output demo-pavois.mp4

Set Shell bash
Set FontSize 20
Set Width 1280
Set Height 720
Set Padding 24
Set TypingSpeed 40ms
Set Theme { "background": "#11131a", "foreground": "#e6e6e6", "cursor": "#dc2626", "selection": "#2a2f3a", "black": "#11131a", "red": "#f87171", "green": "#4ade80", "yellow": "#fbbf24", "blue": "#60a5fa", "magenta": "#c084fc", "cyan": "#22d3ee", "white": "#e6e6e6", "brightBlack": "#6b7280", "brightRed": "#f87171", "brightGreen": "#4ade80", "brightYellow": "#fbbf24", "brightBlue": "#60a5fa", "brightMagenta": "#c084fc", "brightWhite": "#ffffff" }

Hide
Type "export PS1='\033[38;5;203m❯\033[0m '" Enter
Type "clear" Enter
Show

Sleep 1500ms
Type "# A Debian 13 server, straight from the cloud image." Enter
Sleep 1500ms
Type "# How much of it is actually configured securely?" Enter
Sleep 2s

Type "pavois scan pavois@__HOST__ --sudo --on-target" Enter
Sleep 25s
Sleep 4s

Type "# Grade E, and not one file was read to say so:" Enter
Sleep 1800ms
Type "# pavois asked the RUNNING system. sshd -T, sysctl -a, auditctl -l." Enter
Sleep 4s

# Point last.json at the scan the viewer just watched, so `--from` below reuses THAT one and not
# some earlier run. Off camera because it is plumbing, not part of what is being shown.
Hide
Type "cp $(ls -t reports/*.json | head -1) reports/last.json" Enter
Type "clear" Enter
Show

Sleep 500ms
Type "# Which of those gaps can pavois close by itself?" Enter
Sleep 2s
Type "pavois harden plan pavois@__HOST__ --sudo --from reports/last.json" Enter
Sleep 12s

Sleep 2s
Type "grep -A5 'ssh-disable-root-login:' hardening-plan-debian13.yml" Enter
Sleep 5s

Type "# apply: false. Every gap is opt-in, nothing is done behind your back." Enter
Sleep 3s
Type "# Flip the ones you want, run: pavois harden apply, then scan again." Enter
Sleep 3500ms
