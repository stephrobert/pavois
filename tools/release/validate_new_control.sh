#!/usr/bin/env bash
# Prove a NEW control on a real VM: it must PASS, and it must go red when it should.
#
# `mise run regression` cannot do this. It computes `base_pass & failing` (tools/regression.py:99),
# so an id absent from the baseline never enters the intersection: a new control that fails on the
# golden host produces a GREEN regression run, which is exactly the permanent FAIL that CLAUDE.md
# forbids. Issue #304. Until that is fixed, adding a control needs this instead, and the assertion
# has to be explicit: "<id> is in passing", not "regression is green".
#
# It also demands the control FAIL on a host configured to trip it. A control that only ever passes
# is indistinguishable from one that measures nothing, which is the whole argument of #303.
#
# Usage: tools/release/validate_new_control.sh <control-id> [os]     (default os: debian12)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

ID=${1:-}
OSN=${2:-debian12}
[ -n "$ID" ] || { echo "usage: $0 <control-id> [os]" >&2; exit 2; }

VM=pavois-newctl
IMAGE=images:debian/12
work=$(mktemp -d)
fails=0
say() { printf '%s\n' "$*"; }
ok()  { printf '  [ ok ] %s\n' "$1"; }
ko()  { printf '  [FAIL] %s\n         %s\n' "$1" "$2"; fails=$((fails + 1)); }
plain() { sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'; }

cleanup() { incus delete "$VM" --force >/dev/null 2>&1; rm -rf "$work"; say "VM deleted"; }
trap cleanup EXIT INT TERM

say "== a fresh $OSN VM"
incus delete "$VM" --force >/dev/null 2>&1
# init + device + start, never launch + restart: `incus restart` on a fresh VM waits for an ACPI
# shutdown it will not get.
incus init "$IMAGE" "$VM" --vm -c limits.cpu=2 -c limits.memory=3GiB >/dev/null 2>&1 \
  || { say "could not create the VM"; exit 1; }
incus config device add "$VM" eth0 nic network=incusbr0 >/dev/null 2>&1
incus start "$VM" >/dev/null 2>&1 || { say "could not start the VM"; exit 1; }
for _ in $(seq 1 72); do incus exec "$VM" -- true >/dev/null 2>&1 && break; sleep 5; done
incus exec "$VM" -- true >/dev/null 2>&1 || { say "the agent never answered"; exit 1; }
vm() { incus exec "$VM" -- bash -lc "$1" 2>&1 | plain; }
# shellcheck disable=SC2016  # $PRETTY_NAME is expanded inside the VM, not here
say "  $(vm '. /etc/os-release && echo "$PRETTY_NAME"' | tail -1)"

say ""
say "== the engine, and auditd, so the control has something to read"
incus exec "$VM" -- bash -lc 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq curl auditd >/dev/null 2>&1; echo done' >/dev/null 2>&1
meta="https://omnitruck.cinc.sh/stable/cinc-auditor/metadata?p=debian&pv=12&m=x86_64"
if incus exec "$VM" -- bash -lc "set -e
  M=\$(curl -fsSL '$meta'); U=\$(echo \"\$M\" | awk '/^url/{print \$2}'); S=\$(echo \"\$M\" | awk '/^sha256/{print \$2}')
  curl -fsSL \"\$U\" -o /tmp/c.deb && echo \"\$S  /tmp/c.deb\" | sha256sum --check - && dpkg -i /tmp/c.deb" \
  >/dev/null 2>&1; then
  ok "cinc-auditor $(vm 'cinc-auditor version' | tail -1)"
else
  ko "engine install failed" "the omnitruck download or dpkg step did not complete"
  exit 1
fi

say ""
say "== the corpus under test, pushed as it is rendered here"
tar -C profiles/linux -cf "$work/p.tar" "$OSN" 2>/dev/null || { say "no rendered corpus for $OSN"; exit 1; }
incus file push "$work/p.tar" "$VM/root/p.tar" >/dev/null 2>&1
incus exec "$VM" -- bash -lc 'mkdir -p /root/prof && tar -C /root/prof -xf /root/p.tar' >/dev/null 2>&1
say "  $(vm "ls /root/prof/$OSN/controls/*.rb | wc -l" | tail -1) control file(s)"

scan_verdict() { # -> the control's status on this host
  incus exec "$VM" -- bash -lc "cd /root && CHEF_LICENSE=accept-silent cinc-auditor exec /root/prof/$OSN \
    --controls '$ID' --reporter json 2>/dev/null" > "$work/out.json" 2>/dev/null
  python3 - "$work/out.json" "$ID" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"unreadable {e}"); raise SystemExit
for prof in d.get("profiles", []):
    for c in prof.get("controls", []):
        if c.get("id") != sys.argv[2]:
            continue
        rs = c.get("results", [])
        if not rs:
            print("no-result"); raise SystemExit
        st = "failed" if any(r.get("status") == "failed" for r in rs) else rs[0].get("status", "?")
        msg = (rs[0].get("message") or "").strip().replace("\n", " ")[:150]
        print(f"{st}\t{msg}")
        raise SystemExit
print("absent")
PY
}

say ""
say "== 1. it PASSES on this host (the condition CLAUDE.md sets: no permanent FAIL)"
res=$(scan_verdict); st=${res%%	*}; msg=${res#*	}
case "$st" in
  passed) ok "$ID passes ($(vm 'grep -iE "^[[:space:]]*(admin_space_left_action|max_log_file_action)" /etc/audit/auditd.conf 2>/dev/null | tr "\n" " "' | tail -1))" ;;
  failed) ko "$ID FAILS on a host nobody hardened for it" "$msg" ;;
  *)      ko "$ID did not run ($st)" "$msg" ;;
esac

say ""
say "== 2. it FAILS when the host is configured to trip it (a control that only passes measures nothing)"
vm 'printf "max_log_file_action = keep_logs\nadmin_space_left_action = halt\n" >> /etc/audit/auditd.conf' >/dev/null
res=$(scan_verdict); st=${res%%	*}; msg=${res#*	}
case "$st" in
  failed) ok "$ID goes red, and names it: $(printf '%s' "$msg" | cut -c1-110)" ;;
  passed) ko "$ID still passes on a host set to power itself off" "the control does not bite" ;;
  *)      ko "$ID did not run ($st)" "$msg" ;;
esac

say ""
if [ "$fails" -gt 0 ]; then
  say "$fails check(s) failed: $ID is not ready to merge."
  exit 1
fi
say "$ID passes where it must and fails where it must, measured on a real $OSN."
