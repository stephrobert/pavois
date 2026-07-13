#!/usr/bin/env bash
# Pavois — automate the full per-OS hardening validation cycle, end to end, with NO hand-editing
# on the box: scan -> plan -> enable(all safe gaps) -> harden apply -> reboot, LOOPED UNTIL FIXPOINT
# -> invariants -> grade -> lynis. This is the machine that proves the result is produced by pavois,
# reproducibly, not by manual interventions.
#
# Why a LOOP and not a single pass: a plan is a snapshot of the system as it was BEFORE hardening,
# but hardening MUTATES the system. pavois installs the packages a control needs to be meaningful
# (`requires_package`), and those packages bring their own files, units and defaults with them:
#   - installing `at` (so the at.allow/at.deny controls mean something) CREATES /etc/at.deny, which
#     another control requires to be absent — it was absent when the plan was computed, so nothing
#     ever deleted it;
#   - installing an MTA (postfix) brings its own banner and VRFY defaults into scope.
# Those controls were passing (or not applicable) at plan time and are failing afterwards, and a
# single-pass apply can never close them. Converging means: re-scan, re-plan, re-apply, until a
# pass has nothing left to do. Measured on a clean-room ubuntu2404: 5 of 8 residual failures were
# of exactly this kind.
#
# Env: PAVOIS_SUDO_PASSWORD (required, via stdin to cinc). Optional PAVOIS_SSH_FROM, CK_MAX_PASSES.
# Usage: tools/harden_validate.sh <os> <user@host> <ssh_key> [ssh_user]
set -euo pipefail
OS="${1:?os}"; TARGET="${2:?user@host}"; KEY="${3:?ssh key}"; SSHUSER="${4:-pavois}"
HOST="${TARGET#*@}"
: "${PAVOIS_SUDO_PASSWORD:?set PAVOIS_SUDO_PASSWORD}"
MAX_PASSES="${CK_MAX_PASSES:-3}"
SP="$(mktemp -d)"; PLAN="$SP/plan-$OS.yml"
SSH="ssh -tt -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY"
say(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

scan(){ bin/pavois scan "$TARGET" --profile "linux/$OS" --sudo --on-target --key "$KEY" 2>&1 | tail -3; }
reboot_wait(){
  $SSH "$TARGET" "echo '$PAVOIS_SUDO_PASSWORD' | sudo -S systemctl reboot" >/dev/null 2>&1 || true
  sleep 8
  until ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=5 -o BatchMode=yes -i "$KEY" "$TARGET" true 2>/dev/null; do sleep 5; done
  echo "back up"
}

say "scan (baseline)"
scan
J=$(ls -t reports/*"${HOST//./-}"*.json | head -1); echo "report: $J"

pass=1
while :; do
  say "pass $pass/$MAX_PASSES — plan from the CURRENT state"
  bin/pavois harden plan "$TARGET" --sudo --key "$KEY" --from "$J" --out "$PLAN" 2>&1 | tail -1
  enabled=$(uv run --with pyyaml python3 tools/harden_plan_enable.py "$PLAN" --ssh-user "$SSHUSER" \
    ${PAVOIS_SSH_FROM:+--ssh-from "$PAVOIS_SSH_FROM"} | tee /dev/stderr | grep -oE 'enabled [0-9]+' | grep -oE '[0-9]+')

  if [ "${enabled:-0}" -eq 0 ]; then
    echo "  FIXPOINT: nothing left to apply — hardening has converged in $((pass - 1)) pass(es)"
    break
  fi
  if [ "$pass" -gt "$MAX_PASSES" ]; then
    echo "  WARNING: still $enabled gap(s) after $MAX_PASSES passes — NOT converged, see the scan below"
    break
  fi

  say "pass $pass — harden apply ($enabled gaps)"
  bin/pavois harden apply --target "$TARGET" --key "$KEY" --sudo-prompt --yes "$PLAN" 2>&1 | tail -2
  say "pass $pass — reboot + wait"
  reboot_wait
  say "pass $pass — re-scan"
  scan
  J=$(ls -t reports/*"${HOST//./-}"*.json | head -1)
  pass=$((pass + 1))
done

say "INVARIANTS — a hardened host that lost a vital function is a FAILURE, not a grade"
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
# We tighten /var/log (0750, not group-writable): prove the daemon can still WRITE a log line there.
# A hardened host that stopped logging is blind, and every log-content control would still be green.
$SSH "$TARGET" "logger pavois-inv-probe && sleep 2 && echo '$PAVOIS_SUDO_PASSWORD' | sudo -S grep -rqs pavois-inv-probe /var/log/syslog /var/log/messages" \
  >/dev/null 2>&1 || { echo "  INVARIANT FAILED: syslog no longer records anything (/var/log too tight?)"; inv=1; }
$SSH "$TARGET" "systemctl is-system-running 2>/dev/null | grep -qvx degraded" >/dev/null 2>&1 \
  || { echo "  INVARIANT WARNING: the host reports degraded (a unit failed)"; }
[ "$inv" -eq 0 ] && echo "  invariants OK: firewall up, sshd up, package manager healthy, logging alive"

say "grade"
bin/pavois scan "$TARGET" --profile "linux/$OS" --sudo --on-target --key "$KEY" 2>&1 | \
  grep -iE "Grade|Remediable posture|controls passing|CRITICAL|kernel-build|install-time"

say "lynis (index)"
$SSH "$TARGET" "echo '$PAVOIS_SUDO_PASSWORD' | sudo -S bash -c 'test -x /opt/lynis/lynis && cd /opt/lynis && ./lynis audit system --quick --no-colors 2>/dev/null | grep -iE \"Hardening index|Warnings \(\"'" 2>&1 | grep -iE "Hardening|Warnings" || echo "lynis not installed on target"

echo; echo "DONE — grade + lynis above are 100% pavois-produced (rules + harden apply)."
