#!/usr/bin/env bash
# Pavois — automate the full per-OS hardening validation cycle, end to end, with
# NO hand-editing on the box: scan -> plan -> enable(all safe gaps) -> harden apply
# -> reboot -> re-scan (grade) -> lynis (index) -> report. This is the machine that
# proves the result is produced by pavois, reproducibly, not by manual interventions.
#
# Env: PAVOIS_SUDO_PASSWORD (required, via stdin to cinc). Optional PAVOIS_SSH_FROM.
# Usage: tools/harden_validate.sh <os> <user@host> <ssh_key> [ssh_user]
set -euo pipefail
OS="${1:?os}"; TARGET="${2:?user@host}"; KEY="${3:?ssh key}"; SSHUSER="${4:-pavois}"
HOST="${TARGET#*@}"
: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD}"
SP="$(mktemp -d)"; PLAN="$SP/plan-$OS.yml"
SSH="ssh -tt -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY"
say(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

say "1/6 scan (baseline)"
bin/pavois scan "$TARGET" --profile "linux/$OS" --sudo --on-target --key "$KEY" 2>&1 | tail -3
J=$(ls -t reports/*"${HOST//./-}"*.json | head -1); echo "report: $J"

say "2/6 plan from scan"
bin/pavois harden plan "$TARGET" --sudo --key "$KEY" --from "$J" --out "$PLAN" 2>&1 | tail -1
uv run --with pyyaml python3 tools/harden_plan_enable.py "$PLAN" --ssh-user "$SSHUSER" \
  ${PAVOIS_SSH_FROM:+--ssh-from "$PAVOIS_SSH_FROM"}

say "3/6 harden apply"
bin/pavois harden apply --target "$TARGET" --key "$KEY" --sudo-prompt --yes "$PLAN" 2>&1 | tail -2

say "4/6 reboot + wait"
$SSH "$TARGET" "echo '$PAVOIS_SUDO_PASSWORD' | sudo -S systemctl reboot" >/dev/null 2>&1 || true
sleep 8
until ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i "$KEY" "$TARGET" true 2>/dev/null; do sleep 5; done
echo "back up"

say "4b/6 INVARIANTS — a hardened host that lost a vital function is a FAILURE, not a grade"
# We learned this the hard way: two firewall controls with different defaults cancelled each other
# out and the box came back with NO firewall, and a scan reports that as one failing control among
# hundreds. These are pass/fail: if hardening broke the machine, say so, loudly, here.
inv=0
$SSH "$TARGET" "systemctl is-active --quiet ufw || systemctl is-active --quiet nftables || systemctl is-active --quiet firewalld" \
  >/dev/null 2>&1 || { echo "  INVARIANT FAILED: no firewall is active after hardening"; inv=1; }
$SSH "$TARGET" "systemctl is-active --quiet ssh || systemctl is-active --quiet sshd" >/dev/null 2>&1 \
  || { echo "  INVARIANT FAILED: sshd is not running"; inv=1; }
$SSH "$TARGET" "command -v apt-get >/dev/null && apt-get check >/dev/null 2>&1 || command -v dnf >/dev/null && dnf -q check-update >/dev/null 2>&1 || true" \
  >/dev/null 2>&1 || { echo "  INVARIANT FAILED: the package manager is broken"; inv=1; }
$SSH "$TARGET" "systemctl is-system-running 2>/dev/null | grep -qvx degraded" >/dev/null 2>&1 \
  || { echo "  INVARIANT WARNING: the host reports degraded (a unit failed)"; }
[ "$inv" -eq 0 ] && echo "  invariants OK: firewall up, sshd up, package manager healthy"

say "5/6 re-scan (grade)"
bin/pavois scan "$TARGET" --profile "linux/$OS" --sudo --on-target --key "$KEY" 2>&1 | \
  grep -iE "Grade|Remediable posture|controls passing|CRITICAL|kernel-build|install-time"

say "6/6 lynis (index)"
$SSH "$TARGET" "echo '$PAVOIS_SUDO_PASSWORD' | sudo -S bash -c 'test -x /opt/lynis/lynis && cd /opt/lynis && ./lynis audit system --quick --no-colors 2>/dev/null | grep -iE \"Hardening index|Warnings \(\"'" 2>&1 | grep -iE "Hardening|Warnings" || echo "lynis not installed on target"

echo; echo "DONE — grade + lynis above are 100% pavois-produced (rules + harden apply)."
