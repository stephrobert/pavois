# pavois demo, act 2: the same machine after hardening.
#
#   PAVOIS_DEMO_TAPE=tools/demo/pavois-after.tape tools/demo/record.sh
#
# Recorded separately, and concatenated onto act 1, for one reason: `harden apply` converges in
# several passes and reboots the host in between. That is a quarter of an hour of package installs
# and a boot, which nobody wants to watch and no tape can usefully speed up. So the apply is real
# but off camera, and the video SAYS it is off camera. What is on camera is the measurement: a
# scan of the running system after the reboot, with the same command as act 1.
#
# The figures in the closing lines come from the actual run, filled in before recording. They are
# not decoration: a re-record that produces different numbers gets them updated, never rounded.

Output demo-pavois-after.mp4

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
Type "# Same machine. In between: pavois harden apply, then a reboot." Enter
Sleep 1500ms
Type "# Three apply passes, three reboots, seven minutes. Not filmed, not faked." Enter
Sleep 2500ms

Type "pavois scan pavois@__HOST__ --sudo --on-target" Enter
Sleep 35s
Sleep 4s

Type "# 258 controls passing before. 516 now, on the same cloud image." Enter
Sleep 2500ms
Type "# Grade A on everything a remediation can reach: 469 of 470." Enter
Sleep 2500ms
Type "# C overall, because 44 gaps need a repartition or a kernel rebuild." Enter
Sleep 2s
Type "# pavois names them rather than pretending they are done." Enter
Sleep 4s
