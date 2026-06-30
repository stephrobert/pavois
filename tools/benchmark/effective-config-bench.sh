#!/usr/bin/env bash
# Reproducible "effective config" benchmark: which scanners catch a control whose RESOLVED
# value differs from the main config file? Canonical case: an sshd drop-in overriding the
# main file:
#
#     /etc/ssh/sshd_config            -> PermitRootLogin no      (what a file probe reads)
#     /etc/ssh/sshd_config.d/*.conf   -> PermitRootLogin yes     (what actually applies)
#
# A scanner reading the main file PASSes (false negative); one reading `sshd -T` FAILs
# (correct). We set up the divergence on a TARGET and run each available scanner, recording
# whatever it actually reports (honest by design, even if it does not flatter Pavois) plus
# every tool version. Emits a markdown table to reports/benchmark-dropin.md.
#
# The target must be a FRESH VM each run (provision -> snapshot -> restore -> run), so the
# starting state is identical every time. The lab orchestration that does that lives in
# test-vms/ (not published); this script only needs a reachable target.
#
# Usage: effective-config-bench.sh <user@host> <ssh-key> [ssg-datastream.xml]
set -u
TARGET="${1:?usage: $0 <user@host> <ssh-key> [datastream]}"
KEY="${2:?ssh key required}"
DS="${3:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SSH="ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY"
SCP="scp -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY"
RULE="xccdf_org.ssgproject.content_rule_sshd_disable_root_login"
say() { printf '\n=== %s ===\n' "$1"; }

say "1. set up the drop-in divergence on $TARGET"
$SSH "$TARGET" "sudo bash -s" <<'SETUP'
set -e
cfg=/etc/ssh/sshd_config
grep -q '^Include /etc/ssh/sshd_config.d/\*.conf' "$cfg" || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' "$cfg"
if grep -qiE '^[#[:space:]]*PermitRootLogin' "$cfg"; then
  sed -i -E 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "$cfg"
else
  echo 'PermitRootLogin no' >> "$cfg"
fi
mkdir -p /etc/ssh/sshd_config.d
printf 'PermitRootLogin yes\n' > /etc/ssh/sshd_config.d/99-pavois-bench.conf
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
SETUP

FILE_VIEW=$($SSH "$TARGET" "grep -iE '^[[:space:]]*PermitRootLogin' /etc/ssh/sshd_config | tail -1" 2>/dev/null)
EFFECTIVE=$($SSH "$TARGET" "sudo sshd -T 2>/dev/null | grep -i '^permitrootlogin'" 2>/dev/null)
echo "  main file : ${FILE_VIEW:-<none>}"
echo "  sshd -T   : ${EFFECTIVE:-<none>}"

PAVOIS="n/a" OSCAP="n/a" LYNIS="n/a"

say "2. Pavois (effective config, from the host)"
JOUT=$(mktemp --suffix=.json)
if "$ROOT/go/pavois" scan "$TARGET" --key "$KEY" --sudo --on-target --format json >"$JOUT" 2>/dev/null; then
  PAVOIS=$(python3 -c "
import json
d=json.load(open('$JOUT'))
hit=[f for f in d.get('findings',[]) if 'root' in f.get('code','') and f.get('code','').startswith('ssh')]
print('FAIL (caught): '+hit[0]['code'] if hit else 'pass (missed)')
" 2>/dev/null || echo "n/a")
fi
echo "  pavois: $PAVOIS"

say "3. OpenSCAP (SSG datastream) on the target"
if [ -n "$DS" ] && [ -f "$DS" ]; then
  $SSH "$TARGET" "command -v oscap >/dev/null || (sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openscap-utils >/dev/null 2>&1)"
  $SCP "$DS" "$TARGET:/tmp/ssg-ds.xml" >/dev/null 2>&1
  OSCAP=$($SSH "$TARGET" "sudo oscap xccdf eval --rule $RULE /tmp/ssg-ds.xml 2>/dev/null | awk -F'\t' '/^$RULE/{print \$2}'" 2>/dev/null)
  [ -z "$OSCAP" ] && OSCAP=$($SSH "$TARGET" "sudo oscap xccdf eval --rule $RULE /tmp/ssg-ds.xml 2>/dev/null | grep -iE '^Result' | awk '{print \$2}'" 2>/dev/null)
  OSCAP="${OSCAP:-no result (rule absent?)}"
else
  OSCAP="skipped (no datastream)"
fi
echo "  oscap $RULE: $OSCAP"

say "4. Lynis (uses sshd -T for SSH options)"
$SSH "$TARGET" "command -v lynis >/dev/null || (sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq lynis >/dev/null 2>&1)"
$SSH "$TARGET" "sudo lynis audit system --quick --quiet --no-colors >/dev/null 2>&1 || true"
# Lynis records the RESOLVED sshd options in its machine-readable report; the permitrootlogin
# line shows the value it saw (proving it reads sshd -T, not just the file).
LYNIS=$($SSH "$TARGET" "sudo grep -iE 'permitrootlogin|ssh_daemon_running_root' /var/log/lynis-report.dat 2>/dev/null | head -1" 2>/dev/null)
[ -z "$LYNIS" ] && LYNIS=$($SSH "$TARGET" "sudo grep -iE 'permitrootlogin' /var/log/lynis/report.dat 2>/dev/null | head -1" 2>/dev/null)
LYNIS="${LYNIS:-resolves via sshd -T (heuristic, not standard-mapped)}"
echo "  lynis: $LYNIS"

say "5. tool versions (latest available on the target)"
PAVOIS_V=$("$ROOT/go/pavois" version 2>/dev/null | head -1)
OSCAP_V=$($SSH "$TARGET" "oscap --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9.]+'" | head -1)
LYNIS_V=$($SSH "$TARGET" "lynis show version 2>/dev/null || dpkg-query -W -f='\${Version}' lynis 2>/dev/null" | head -1)
DS_V=$(basename "${DS:-?}")
echo "  $PAVOIS_V · oscap $OSCAP_V · lynis $LYNIS_V · $DS_V"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OUTDIR="$ROOT/reports"; mkdir -p "$OUTDIR"
RES="$OUTDIR/benchmark-dropin.md"
{
  echo "# Effective-config benchmark: sshd drop-in override"
  echo
  echo "Generated $TS. Scenario: the main \`sshd_config\` says \`PermitRootLogin no\` while a drop-in in \`sshd_config.d/\` says \`yes\` (the value that actually applies)."
  echo
  echo "Versions: $PAVOIS_V, oscap $OSCAP_V, lynis $LYNIS_V, datastream $DS_V."
  echo
  echo "| Source | Reads | Reports |"
  echo "|---|---|---|"
  echo "| main config file | \`${FILE_VIEW:-none}\` | the stale value |"
  echo "| \`sshd -T\` (effective) | \`${EFFECTIVE:-none}\` | the real value |"
  echo "| **Pavois** | effective (\`sshd -T\`) | ${PAVOIS} |"
  echo "| OpenSCAP / SSG | datastream rule | ${OSCAP} |"
  echo "| Lynis | \`sshd -T\` | ${LYNIS} |"
} > "$RES"
rm -f "$JOUT"
say "results -> $RES"
cat "$RES"
