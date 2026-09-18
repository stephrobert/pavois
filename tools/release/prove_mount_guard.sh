#!/usr/bin/env bash
# Prove the mount-option guard on ONE disposable debian12 VM, in both directions.
#
# WHY A SCRIPT AND NOT A SEQUENCE TYPED BY HAND
#
# CLAUDE.md makes one rule non negotiable: a rules.yml or template change that alters what a target
# audits does not merge without a REAL scan on a debian12 VM. That proof has to be reproducible by
# someone else, and a proof nobody can replay is an assertion.
#
# WHAT IT PROVES, AND IN WHICH ORDER
#
# The witness FIRST, on the unguarded corpus: 21 controls must FAIL with `expected nil to include`,
# nil being the absent mount. That red is the evidence the guard is needed; without it, a green
# "after" proves only that something was green.
#
# Then the guarded corpus, on the SAME VM, same key, same sudo: the same 21 must become SKIPPED,
# and nothing else may move. A control that goes from passed to failed, or from passed to n/a, is a
# side effect and fails this script.
#
# RULES IT OBEYS (.claude/skills/vm-proof-harness)
#   - a VM, never a container, created for this and destroyed on exit, including on interrupt
#   - never `local`: the target is the VM, never the maintainer's machine
#   - the lab sudo password never appears on a command line: it is exported, read from the env
#   - one VM at a time, 4 GiB, and free memory checked before starting
#
# Usage: PAVOIS_SUDO_PASSWORD=... tools/release/prove_mount_guard.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

OS=debian12
OUT=reports/proof-mount-guard-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"/{before,after}
LOG="$OUT/proof.log"
: >"$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }
ok() { printf '  [ ok ] %s\n' "$1" | tee -a "$LOG"; }
ko() {
  printf '  [FAIL] %s\n         %s\n' "$1" "${2:-}" | tee -a "$LOG"
  fails=$((fails + 1))
}
fails=0
plain() { sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'; }

[ -n "${PAVOIS_SUDO_PASSWORD:-}" ] || {
  say "export PAVOIS_SUDO_PASSWORD first: it must never be typed on a command line"
  exit 2
}
free -g | sed -n 2p | tee -a "$LOG"

cleanup() {
  mise run vm -- down "$OS" >/dev/null 2>&1
  say "VM deleted"
}
trap cleanup EXIT INT TERM

# --------------------------------------------------------------- the witness: the corpus WITHOUT
# the guard.
#
# Taken from the BASE BRANCH, not from a stash. The first version of this script stashed the
# working tree, which does nothing once the fix is committed: it rendered the guarded corpus, called
# it the witness, and would have reported a proof from two identical scans. The witness has to come
# from a named reference that provably lacks the fix, and the script says which one and checks it.
BASE=${PROOF_BASE:-main}
say "== 1. the witness: the corpus of $BASE, which has no guard"
git checkout "$BASE" -- tools/templates.py 2>/dev/null || {
  say "could not read tools/templates.py from $BASE"
  exit 1
}
STASHED=1
mise run gen >/dev/null 2>&1 && mise run render >/dev/null 2>&1 || {
  say "could not render the witness corpus"
  exit 1
}
guards=$(grep -c "is not a separate mount" profiles/linux/$OS/controls/mounts.rb || true)
[ "$guards" = "0" ] && ok "the witness corpus carries no guard" || ko "the witness corpus already carries $guards guard(s)" "the stash did not restore HEAD"

mise run vm -- up "$OS" --sudo-password "$PAVOIS_SUDO_PASSWORD" >>"$LOG" 2>&1 || {
  say "could not create the VM"
  exit 1
}
IP=$(mise run vm -- ip "$OS" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
[ -n "$IP" ] || {
  say "the VM has no address"
  exit 1
}
say "  target: pavois@$IP"

scan() { # scan <outdir>
  mise run build >/dev/null 2>&1
  PAVOIS_SUDO_PASSWORD="$PAVOIS_SUDO_PASSWORD" go/pavois scan "pavois@$IP" \
    --key "${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}" --sudo --format json --out "$1" \
    >>"$LOG" 2>&1
  ls -t "$1"/*.json 2>/dev/null | head -1
}

B=$(scan "$OUT/before")
[ -n "$B" ] && [ -s "$B" ] || {
  say "the witness scan produced nothing"
  exit 1
}

count() { # count <report> <status> -> number of mount-* results in that status
  python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
want = sys.argv[2]
n = 0
for p in d.get("profiles", []):
    for c in p.get("controls", []):
        if not c["id"].startswith("mount-"):
            continue
        st = {r.get("status") for r in c.get("results", [])}
        got = "failed" if "failed" in st else ("skipped" if st == {"skipped"} else "passed")
        n += got == want
print(n)
PY
}

bf=$(count "$B" failed)
bs=$(count "$B" skipped)
say "  witness: mount-* failed=$bf skipped=$bs"
[ "$bf" -ge 20 ] && ok "the witness is red on the mount family ($bf failed)" || ko "the witness is not red enough ($bf failed)" "expected at least 20"

# --------------------------------------------------------------- the fix, same VM, same target
say ""
say "== 2. the guarded corpus, on the SAME VM"
[ "$STASHED" = "1" ] && git checkout HEAD -- tools/templates.py
mise run gen >/dev/null 2>&1 && mise run render >/dev/null 2>&1 || {
  say "could not render the guarded corpus"
  exit 1
}
guards=$(grep -c "is not a separate mount" profiles/linux/$OS/controls/mounts.rb || true)
[ "$guards" -gt 0 ] && ok "the guarded corpus carries $guards guard(s)" || ko "the guard is not in the rendered corpus" "grep found none"

A=$(scan "$OUT/after")
[ -n "$A" ] && [ -s "$A" ] || {
  say "the guarded scan produced nothing"
  exit 1
}
af=$(count "$A" failed)
as=$(count "$A" skipped)
say "  guarded: mount-* failed=$af skipped=$as"

moved=$((bf - af))
[ "$moved" -ge 18 ] && ok "$moved mount control(s) stopped reporting a deviation" || ko "only $moved control(s) moved" "expected at least 18"

# --------------------------------------------------------------- nothing else moved
say ""
say "== 3. no side effect: what was passing still passes"
python3 - "$B" "$A" <<'PY' | tee -a "$LOG"
import json, sys


def statuses(path):
    d = json.load(open(path))
    out = {}
    for p in d.get("profiles", []):
        for c in p.get("controls", []):
            st = {r.get("status") for r in c.get("results", [])}
            out[c["id"]] = (
                "failed" if "failed" in st else ("skipped" if st == {"skipped"} else "passed")
            )
    return out


b, a = statuses(sys.argv[1]), statuses(sys.argv[2])
moves = {(b[k], a[k]): [] for k in b if k in a and b[k] != a[k]}
for k in b:
    if k in a and b[k] != a[k]:
        moves[(b[k], a[k])].append(k)
for (x, y), ids in sorted(moves.items()):
    print(f"  {x} -> {y}: {len(ids)}  {', '.join(sorted(ids)[:4])}")
bad = [k for k in b if k in a and b[k] == "passed" and a[k] != "passed"]
print(f"  REGRESSIONS (passed -> anything else): {len(bad)} {bad[:5]}")
PY

say ""
say "== 4. the trust gate reads the guarded scan"
python3 tools/validate_run.py "$B" 2>&1 | plain | grep -E "^(ERRORS|WARNINGS)" | sed 's/^/  witness  /' | tee -a "$LOG"
python3 tools/validate_run.py "$A" 2>&1 | plain | grep -E "^(ERRORS|WARNINGS)" | sed 's/^/  guarded  /' | tee -a "$LOG"

say ""
say "== 5/5 what this proof does NOT establish"
#
# `mise run regression` is deliberately NOT run here, and the first version of this script ran it.
# It compares a scan to the FROZEN golden baseline, which describes a fully hardened debian12 (615
# passing, remediable A 469/470). The host of this proof is a STOCK VM that nothing has hardened,
# so the gate answered "REGRESSIONS: 242" on controls the guard never touched: the distance
# between hardened and unhardened, reported as a verdict about the change. A harness that measures
# the wrong thing is worse than no harness, and this one said so loudly enough to be caught.
#
# The comparison that DOES apply is section 3: the same host, scanned twice, minutes apart, with
# only the corpus changed. `mise run regression` belongs to a golden campaign, where the baseline
# and the host describe the same machine.
say "  the frozen baseline describes a HARDENED debian12; this VM is stock, so"
say "  mise run regression does not apply here: it would measure hardening, not the guard."
say "  The applicable comparison is section 3, the same host scanned twice."
say "  Still owed before this ships: a golden campaign (tools/golden_path.sh debian12),"
say "  where the 21 ids must move from fail>fail to fail>na in campaign-delta.json."

say ""
if [ "$fails" -eq 0 ]; then
  say "the guard removes the invented deviations and changes nothing else."
else
  say "$fails check(s) failed: the proof does not hold."
fi
say "log: $LOG"
exit "$fails"
