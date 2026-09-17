#!/usr/bin/env bash
# The complete first-run scenario, on one disposable VM, every step an assertion.
#
# WHY THIS EXISTS
#
# Two releases in a row shipped a binary that could not do its job, and both got through the same
# way: every test ran inside the repository, where profiles/ and docs/reference/ are on disk.
#   v0.1.0  the rule corpus was compiled in, and the lookup asked the filesystem -> no profile
#           resolved on any machine that was not a checkout.
#   v0.1.1  the same defect one floor down: `harden plan` read its reference from the CURRENT
#           DIRECTORY, so scan worked and remediation did not.
# Both were found by a user on a fresh VM, not by the test suite. This is that user, automated.
#
# It is also the regression suite for every issue closed that way. A closed issue that is only
# described in a changelog comes back; a closed issue with a line here does not.
#
# THE RULES IT OBEYS (see .claude/skills/vm-proof-harness)
#   - a VM, never a container: 259 of 789 controls are meaningless without a kernel of your own
#   - never `local` on a workstation: `harden plan` writes on the target (#206)
#   - one VM, deleted on exit, including on interrupt
#   - no output is ever swallowed: a step that fails prints what it was told
#
# Usage:
#   tools/release/scenario.sh                     # the working tree's binary, built as a release
#   tools/release/scenario.sh --binary released   # the published artifact, as a user gets it
#   tools/release/scenario.sh --os ubuntu2404 --keep
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

VM=pavois-scenario
IMAGE=images:ubuntu/24.04
RELEASE=${PAVOIS_VERSION:-}
SOURCE=local        # local | released
KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --binary) SOURCE=$2; shift 2 ;;
    --os)     IMAGE="images:${2/ubuntu2404/ubuntu\/24.04}"; shift 2 ;;
    --keep)   KEEP=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

OUT=reports/scenario-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
LOG="$OUT/scenario.log"
: > "$LOG"

fails=0
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
ok()   { printf '  [ ok ] %s\n' "$1" | tee -a "$LOG"; }
ko()   { printf '  [FAIL] %s\n         %s\n' "$1" "$2" | tee -a "$LOG"; fails=$((fails + 1)); }
note() { printf '  [note] %s\n' "$1" | tee -a "$LOG"; }
# pavois styles its own output, so `grade E` on screen is `grade \e[1mE\e[0m` in a pipe. A witness
# check once went red on a scan that had plainly succeeded. Every match goes through this.
plain() { sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'; }

# Match WITHOUT a pipe. `set -o pipefail` and `grep -q` are a false-negative machine: grep exits on
# the first match and closes the pipe, the writer takes a SIGPIPE, and pipefail then reports the
# whole pipeline as failed even though the match succeeded. It only bites when the output is large
# enough that the writer is still writing, so it passes on a doctor line and fails on a full scan
# report. That is what reported "scan local --sudo produced no grade" while printing the grade it
# had just failed to find.
has()   { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }   # has <needle> <haystack>
rx()    { [[ "$2" =~ $1 ]]; }                                      # rx <regex> <haystack>
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

work=$(mktemp -d)
cleanup() {
  if [ "$KEEP" = 1 ]; then
    say "VM kept: incus exec $VM -- bash   (delete it with: incus delete $VM --force)"
  else
    incus delete "$VM" --force >/dev/null 2>&1
    say "VM deleted"
  fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

vm()   { incus exec "$VM" -- "$@" 2>&1 | plain; }
vmsh() { incus exec "$VM" -- bash -lc "$1" 2>&1 | plain; }
# As the unprivileged user, which is how a person actually runs this. Root hides #281 entirely.
asuser() { incus exec "$VM" -- su - tester -c "$1" 2>&1 | plain; }
# Over ssh, as the apply phase does, and as `pavois scan user@host` does. -F /dev/null because a
# global `Host *` ProxyJump in ~/.ssh/config breaks direct connections with a misleading
# "UNKNOWN port 65535"; -o UserKnownHostsFile=/dev/null because -F does not neutralise known_hosts.
sshvm() {
  ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR -o ConnectTimeout=20 -i "${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}" \
      "tester@$VM_IP" "$1" 2>&1 | plain
}

# ---------------------------------------------------------------- the binary under test
if [ "$SOURCE" = released ]; then
  RELEASE=${RELEASE:-$(gh release view --repo stephrobert/pavois --json tagName --jq .tagName 2>/dev/null)}
  say "== the published binary of ${RELEASE}, downloaded and verified as a user would"
  ( cd "$work" && gh release download "$RELEASE" --repo stephrobert/pavois \
      --pattern 'pavois-linux-amd64' --pattern 'checksums.txt' >/dev/null 2>&1 ) \
    || { say "could not download $RELEASE"; exit 1; }
  ( cd "$work" && sha256sum --ignore-missing --check checksums.txt ) | sed 's/^/  /' | tee -a "$LOG"
  if ( cd "$work" && gh attestation verify pavois-linux-amd64 --repo stephrobert/pavois >/dev/null 2>&1 ); then
    note "SLSA attestation verified"
  else
    ko "the SLSA attestation did not verify" "gh attestation verify pavois-linux-amd64"
  fi
  BIN="$work/pavois-linux-amd64"
else
  say "== the working tree, built exactly as the release workflow builds it"
  # NOT `mise run build`: that links against this machine's libc and stamps the version `dev`, so
  # it is not the artifact that ships. And both embed dirs have to be populated, or the binary
  # falls back to disk, which is invisible from inside a checkout.
  mise run embed:all >/dev/null 2>&1 || { say "embed failed (mise run embed:all)"; exit 1; }
  ( cd go && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
      -ldflags="-s -w -X pavois/cmd.version=${PAVOIS_LOCAL_VERSION:-0.0.0-scenario}" \
      -o "$work/pavois" . ) || { say "go build failed"; exit 1; }
  BIN="$work/pavois"
fi
say "  $(basename "$BIN"), $(stat -c%s "$BIN") bytes"

# ---------------------------------------------------------------- a machine that has nothing
#
# A FUNCTION, because the scenario needs this twice. The two convergences cannot share a VM: the
# first one hardens it, and the second then measures ground the first changed. That is not a
# hypothesis, it is #288: after a full apply the converge mounts the scratch directories `noexec`,
# and `scan --on-target` dies with `sh: 1: env: Permission denied` (exit 126). Reordering does not
# help, since whichever runs first spoils the other.
provision_vm() {
  incus delete "$VM" --force >/dev/null 2>&1
  # init + device + start, NOT launch + restart: `incus restart` on a fresh VM waits for an ACPI
  # shutdown it will not get, and hangs for as long as you let it.
  incus init "$IMAGE" "$VM" --vm -c limits.cpu=2 -c limits.memory=2GiB >/dev/null 2>&1 \
  || { say "could not create the VM"; return 1; }
  incus config device add "$VM" eth0 nic network=incusbr0 >/dev/null 2>&1
  incus start "$VM" >/dev/null 2>&1 || { say "could not start the VM"; return 1; }
  for _ in $(seq 1 72); do incus exec "$VM" -- true >/dev/null 2>&1 && break; sleep 5; done
  incus exec "$VM" -- true >/dev/null 2>&1 || { say "the agent never answered"; return 1; }
  say "  up: $(vmsh '. /etc/os-release && echo "$PRETTY_NAME"' | tail -1)"

  # An unprivileged account with passwordless sudo. Running everything as root would hide #281, which
  # is about what happens when you are NOT root, and that is how people actually run a scanner.
  vmsh 'id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester' >/dev/null
  vmsh 'echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester && chmod 0440 /etc/sudoers.d/tester' >/dev/null

  # sshd and this machine's public key, because `harden apply` has no local path: it scp's a recipe to
  # the target and runs cinc-client there (#200, the ssh/scp route is hard-wired). So the apply half
  # of the scenario runs FROM here, over ssh, INTO the VM. That is also the documented usage, and it
  # keeps the rule that nothing hardens the workstation: this machine is the control host, the VM is
  # the target.
  PUBKEY=$(cat "${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}.pub" 2>/dev/null || true)
  if [ -n "$PUBKEY" ]; then
  vmsh 'mkdir -p /home/tester/.ssh && chmod 700 /home/tester/.ssh' >/dev/null
  # Written through a here-doc on the VM rather than scp: since OpenSSH 9, scp speaks SFTP and these
  # cloud images ship no sftp-server.
  vmsh "printf '%s\n' '$PUBKEY' > /home/tester/.ssh/authorized_keys" >/dev/null
  vmsh 'chmod 600 /home/tester/.ssh/authorized_keys && chown -R tester:tester /home/tester/.ssh' >/dev/null
  vmsh 'command -v sshd >/dev/null || (apt-get update -qq && apt-get install -y -qq openssh-server)' >/dev/null
  vmsh 'systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null' >/dev/null
  fi
  VM_IP=$(vmsh "ip -4 -o addr show scope global | awk '{print \$4}' | cut -d/ -f1 | head -1" | tr -d '[:space:]')
  say "  reachable at ${VM_IP:-<no address>}"

  incus file push "$BIN" "$VM/usr/local/bin/pavois" >/dev/null 2>&1 || { say "push failed"; return 1; }
  vm chmod 0755 /usr/local/bin/pavois >/dev/null
  say "  installed at /usr/local/bin/pavois, and nothing else was copied"
}

say ""
say "== a fresh VM, which has never seen this project"
provision_vm || exit 1

# ---------------------------------------------------------------- 1. it answers at all
say ""
say "--- 1. the CLI answers the things every CLI is asked"
out=$(asuser 'pavois --version')
if rx 'pavois +[0-9]' "$(lower "$out")"; then
  ok "pavois --version answers ($(printf '%s' "$out" | grep -oiE 'pavois +[0-9][^ ]*' | head -1))"   # #284
else
  ko "pavois --version is not recognised (#284)" "$(printf '%s' "$out" | head -2 | tr '\n' ' ')"
fi
out=$(asuser 'pavois version')
rx 'pavois +[0-9]' "$(lower "$out")" \
  && ok "pavois version agrees with it" \
  || ko "the version subcommand disagrees with --version" "$(printf '%s' "$out" | tail -1)"

# ---------------------------------------------------------------- 2. before the engine exists
say ""
say "--- 2. what a machine with no scan engine is told"
out=$(asuser 'pavois doctor')
printf '%s\n' "$out" >> "$LOG"
if has cinc "$(lower "$out")"; then
  ok "doctor names the missing engine, before any scan is attempted"
else
  ko "doctor does not say the engine is missing" "$(printf '%s' "$out" | tail -3 | tr '\n' ' ')"
fi
if has 'embedded in this binary' "$(lower "$out")"; then
  ok "doctor reports the rule corpus as embedded"
else
  ko "doctor does not see the embedded corpus" "$(printf '%s' "$out" | grep -i 'corpus' | head -1)"
fi

# The flag whose whole purpose is "the engine is missing, install it" used to be unreachable in
# exactly that case: the scan died on OS detection first and never mentioned the flag (#283).
out=$(asuser 'pavois scan local --bootstrap-cinc')
printf '%s\n' "$out" >> "$LOG"
if has bootstrap-cinc "$(lower "$out")"; then
  ok "--bootstrap-cinc on a local target says what it does (#283)"
else
  ko "--bootstrap-cinc is silent on a local target (#283)" \
     "$(printf '%s' "$out" | grep -i error | head -1 | cut -c1-140)"
fi

# One failure, one message. An engine refusal used to be reported as a verdict, and the caller then
# complained about a report file that was never written (#282).
out=$(asuser 'pavois scan local --sudo')
printf '%s\n' "$out" >> "$LOG"
if has 'no such file or directory' "$(lower "$out")"; then
  ko "a failed scan still reports a missing report file (#282)" \
     "$(printf '%s' "$out" | grep -i 'no such file' | head -1 | cut -c1-140)"
else
  ok "a failed scan reports one cause, not a second misleading error (#282)"
fi

# ---------------------------------------------------------------- 3. the engine, as documented
say ""
say "--- 3. install the engine, running THE DOCUMENTATION'S OWN COMMANDS"
# Not a copy of them. The block comes from site/src/data/install.ts, which is what both install
# pages render (tools/lint_install_docs.py fails the build if a page grows its own copy). A harness
# that retypes a documented command proves the retyped version: the day the page changed, this
# would have kept certifying the old recipe.
#
# Exactly two substitutions, and they are the two the documentation tells the reader to make: the
# omnitruck platform keys (the page lists el/8, el/9, debian/12, ubuntu/24.04...) and the package
# manager (the block's own trailing comment says "Debian/Ubuntu: sudo apt install ./<file>").
# Nothing else is touched, so any other drift in the page breaks this step, which is the point.
#
# A function for the same reason provision_vm() is one: the ssh transport gets its own VM (#288),
# and that VM needs an engine too.
install_engine() {
  {
    echo 'set -e'
    echo 'command -v curl >/dev/null || { apt-get update -qq && apt-get install -y -qq curl; }'
    mise exec -- node --experimental-strip-types tools/doc_commands.mjs --id engine-install \
      | sed -e 's|p=el&pv=9|p=ubuntu\&pv=24.04|' \
            -e 's|sudo dnf install -y|sudo apt-get install -y|' \
            -e 's|^pavois doctor.*|true|'
  } > "$work/install-cinc.sh"
  incus file push "$work/install-cinc.sh" "$VM/root/install-cinc.sh" >/dev/null 2>&1
  if incus exec "$VM" -- bash /root/install-cinc.sh >>"$LOG" 2>&1; then
    ok "cinc-auditor $(vm cinc-auditor version | tail -1) installed, checksum checked"
    vm rm -f /root/install-cinc.sh >/dev/null
    return 0
  fi
  ko "could not install the engine" "its output is in $LOG"
  return 1
}

say "  the command under test, as the page gives it:"
mise exec -- node --experimental-strip-types tools/doc_commands.mjs --id engine-install \
  | sed 's/^/    /' | tee -a "$LOG"
install_engine || exit "$fails"
out=$(asuser 'pavois doctor')
has ready "$(lower "$out")" \
  && ok "doctor now says the host is ready" \
  || ko "doctor still does not say ready" "$(printf '%s' "$out" | tail -2 | tr '\n' ' ')"

# ---------------------------------------------------------------- 4. the first scan
say ""
say "--- 4. the first scan, run the way every entry point recommends it"
# `pavois scan local --sudo` is what doctor prints, what the site features and what the README says.
# It was refused by the engine, from an unprivileged account, on the very first try (#281).
out=$(asuser 'cd ~ && pavois scan local --sudo --out ~/reports')
printf '%s\n' "$out" >> "$LOG"
if has 'sudo is only valid' "$(lower "$out")"; then
  ko "scan local --sudo is still refused by the engine (#281)" \
     "every entry point recommends this exact form"
elif rx 'grade [a-e]' "$(lower "$out")"; then
  ok "scan local --sudo graded the host ($(printf '%s' "$out" | grep -oiE 'grade [A-E]' | head -1))"
else
  ko "scan local --sudo produced no grade (#281)" "$(printf '%s' "$out" | tail -3 | tr '\n' ' ' | cut -c1-180)"
fi
# A report the user cannot delete without sudo is a report they will curse.
owner=$(vmsh 'find /home/tester/reports -maxdepth 1 -type f -printf "%u\n" 2>/dev/null | sort -u | tr "\n" " "')
case "$(printf '%s' "$owner" | tr -d '[:space:]')" in
  tester|"") ok "the reports belong to the user who asked for the scan" ;;
  *)         ko "the reports are owned by $owner" "the caller cannot delete their own report" ;;
esac

# ---------------------------------------------------------------- 5. the other half of the product
say ""
say "--- 5. remediation, from every directory (this is #286)"
# The reference used to be resolved against the CURRENT DIRECTORY, so the error path moved when you
# cd'd. `scan` honoured the self-contained promise and `harden` did not.
for dir in '~' /tmp /; do
  # --out gets a DIRECTORY on purpose: `scan --out` is a directory and `harden plan --out` was a
  # file, so the same flag meant opposite things on two commands people run one after the other.
  out=$(asuser "cd $dir && pavois harden plan local --out ~/reports")
  printf '%s\n' "$out" >> "$LOG"
  if has 'read reference' "$out" || has 'no hardening reference' "$out"; then
    ko "harden plan cannot read its reference from $dir (#286)" \
       "$(printf '%s' "$out" | grep -iE 'reference' | head -1 | cut -c1-140)"
  elif rx 'remediation|plan|control' "$(lower "$out")"; then
    ok "harden plan produced a plan from $dir"
  else
    ko "harden plan produced no plan from $dir" "$(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
  fi
done

# The same defect reached three more commands, which the issue did not name: they all read the
# reference under findRoot(). `norms` and `oscal` failed WORSE than harden, by succeeding with an
# empty catalogue.
for c in "rules --os ubuntu2404" "oscal" "norms"; do
  out=$(asuser "cd /tmp && pavois $c")
  name=${c%% *}
  if rx 'read reference|no hardening reference|no such file' "$out"; then
    ko "pavois $name cannot read the reference outside a checkout (#286)" \
       "$(printf '%s' "$out" | grep -iE 'reference|no such' | head -1 | cut -c1-140)"
  elif [ "$(printf '%s' "$out" | wc -c)" -lt 200 ]; then
    ko "pavois $name returned almost nothing outside a checkout" \
       "an empty catalogue is worse than an error: it succeeds and reports nothing"
  else
    ok "pavois $name works outside a checkout ($(printf '%s' "$out" | wc -c) bytes)"
  fi
done

# ------------------------------------------------- 5b. the assets no command above would have missed
say ""
say "--- 5b. everything else the binary has to carry, declared by the binary itself"
# Phase 5 exercises the three assets that ANSWER when they are missing. Three more fail silently,
# and v0.1.2 shipped with all of them empty while every check above was green:
#
#   audit.rules            harden apply pushed an EMPTY audit ruleset and reported success
#   behavioral-probes.yml  pavois verify answered with an internal repository path
#   baseline.yml           oscal keeps hardcoded defaults on any error, so with the reference
#                          embedded and this one not, it SUCCEEDS and publishes a catalogue
#                          declaring itself version 0.0.0, released 1970-01-01
#
# `pavois doctor` enumerates all six with a count each, so one command covers them and a user who
# meets "this binary embeds none" has something to run.
out=$(asuser 'cd /tmp && pavois doctor')
printf '%s\n' "$out" >> "$LOG"
assets='hardening reference|norm catalogue|baseline identity|audit ruleset|behavioral probes|kernel-build recipes'
missing=$(printf '%s\n' "$out" | plain | grep -E '^\s*\[FAIL\]' | grep -E "$assets")
carried=$(printf '%s\n' "$out" | plain | grep -cE '^\s*\[OK  \].*('"$assets"')')
if [ -n "$missing" ]; then
  ko "doctor reports $(printf '%s\n' "$missing" | grep -c .) embedded asset(s) missing" \
     "$(printf '%s' "$missing" | head -1 | sed 's/^ *//' | cut -c1-140)"
elif [ "${carried:-0}" -lt 6 ]; then
  ko "doctor accounts for only $carried of the 6 embedded assets" \
     "either an asset was added without a doctor line, or a line was renamed; both hide a gap"
else
  ok "doctor accounts for all 6 embedded assets, from /tmp"
  printf '%s\n' "$out" | plain | grep -E '^\s*\[OK  \].*('"$assets"')' | sed 's/^ */      /'
fi

# Embedded is not the same as CORRECT, and this is the one that fails without failing: the check is
# on the CONTENT of the catalogue, never on the exit code.
meta=$(asuser 'cd /tmp && pavois oscal' | head -40)
if rx '"version": *"0\.0\.0"|1970-01-01' "$meta"; then
  ko "the OSCAL catalogue publishes itself as version 0.0.0 / 1970-01-01" \
     "baseline.yml is not embedded; readBaseline silently kept its defaults, and nothing failed"
elif has '"version"' "$meta"; then
  ok "the OSCAL catalogue carries the real baseline metadata ($(printf '%s' "$meta" | grep -m1 '"version"' | tr -d ' ",' | cut -c1-40))"
else
  ko "pavois oscal emitted no catalogue metadata" "$(printf '%s' "$meta" | tail -1 | cut -c1-140)"
fi

# 203.0.113.x is TEST-NET-3 and answers nothing, which is enough: the question is whether verify can
# READ ITS PROBES, not whether the target is up. It used to fail before reaching the network.
out=$(asuser 'cd /tmp && timeout 60 pavois verify 203.0.113.9' 2>&1)
if rx 'behavioral-probes.yml|no behavioral probes' "$out"; then
  ko "pavois verify cannot find its probes outside a checkout" \
     "$(printf '%s' "$out" | head -1 | cut -c1-140)"
else
  ok "pavois verify reads its probes and reaches the target"
fi

say ""
say "--- 6. nothing was dropped beside the binary to make any of that work"
stray=$(vmsh 'test -e /docs -o -e /root/docs -o -e /home/tester/docs -o -e /usr/local/bin/docs && echo yes')
if has yes "$stray"; then
  ko "a docs/ tree exists on the VM" "the result would be meaningless: that is the file it used to need"
else
  ok "no docs/ and no profiles/ anywhere: everything came from inside the binary"
fi

# ---------------------------------------------------------------- 7. the advice on failure
say ""
say "--- 7. what an unreachable SSH target is told"
# The hint used to recommend --key even when --key had just been passed, sending the reader back to
# their own command line instead of to the machine refusing them (#285).
#
# The target is a name in .invalid, which RFC 2606 guarantees will never resolve: the answer is
# immediate and identical everywhere. An unroutable address (203.0.113.7, TEST-NET) was tried first
# and made this step wait out a TCP timeout, which read as a hung scenario.
out=$(asuser 'pavois scan pavois@pavois-nowhere.invalid --key /dev/null')
printf '%s\n' "$out" >> "$LOG"
if has 'so pass --key' "$(lower "$out")"; then
  ko "the hint still recommends --key when --key was passed (#285)" \
     "$(printf '%s' "$out" | grep -i 'pass --key' | head -1 | cut -c1-140)"
elif has authorized_keys "$(lower "$out")"; then
  ok "the hint points at the target, not at the command line (#285)"
else
  note "no key-related hint was produced: $(printf '%s' "$out" | grep -i 'could not reach' | head -1 | cut -c1-90)"
fi

# ---------------------------------------------------------------- 8. the other half of the product
say ""
say "--- 8a. remediation applied LOCALLY, by the binary on the machine it is hardening (#200)"
#
# `harden apply` invoked ssh and scp unconditionally, so a local target meant `ssh -tt local …`.
# `pavois scan local` worked and `pavois harden apply local` could not, on the target every user
# tries first: their own machine. Worse than a clean refusal, because a `Host local` entry in
# ~/.ssh/config would have sent the converge to an arbitrary machine.
#
# This runs INSIDE the VM, which is the only honest way to test it: the machine being hardened is
# the machine running the command, and it is disposable.
planlocal='~/plan-local.yml'
out=$(asuser "cd ~ && pavois harden plan local --out $planlocal")
printf '%s\n' "$out" >> "$LOG"
if has 'read reference' "$out" || has 'no hardening reference' "$out"; then
  ko "harden plan local could not read its reference" "$(printf '%s' "$out" | tail -1 | cut -c1-140)"
else
  ok "harden plan local wrote a plan for itself"
fi

# A plan is born with `apply: false` on every gap, because flipping them is the operator's decision.
# So an apply straight off a fresh plan converges nothing, and the first version of this step
# asserted against a recipe that was legitimately empty. tools/harden_plan_enable.py encodes the
# enable policy (every gap on, danger items off unless boot-safe, ssh lock-out guards set), which is
# the automation half of "the result is produced by pavois, not by hand-editing YAML".
vmsh 'command -v python3 >/dev/null || (apt-get update -qq && apt-get install -y -qq python3 python3-yaml)' >/dev/null
incus file push tools/harden_plan_enable.py "$VM/home/tester/enable.py" >/dev/null 2>&1
vmsh 'chown tester:tester /home/tester/enable.py' >/dev/null
enabled=$(asuser "cd ~ && python3 enable.py $planlocal --ssh-user tester 2>&1 | tail -2")
printf '%s\n' "$enabled" >> "$LOG"
if rx 'enabled [0-9]+' "$enabled"; then
  ok "the plan's gaps were enabled ($(printf '%s' "$enabled" | grep -oE 'enabled [0-9]+' | head -1))"
else
  ko "could not enable the plan's gaps" "$(printf '%s' "$enabled" | tr '\n' ' ' | cut -c1-140)"
fi

# --dry-run compiles the Chef recipe and prints it WITHOUT converging: the cheapest proof that the
# embedded apply-time data reaches the recipe. audit.rules used to be read with the error discarded,
# so the recipe compiled happily with an empty ruleset and the apply reported success.
recipe=$(asuser "cd ~ && pavois harden apply --target local --yes --dry-run $planlocal")
printf '%s\n' "$recipe" >> "$LOG"
if has 'ssh:' "$recipe" || has 'could not resolve hostname local' "$(lower "$recipe")"; then
  ko "harden apply still tries to ssh to a host named \"local\" (#200)" \
     "$(printf '%s' "$recipe" | tail -2 | tr '\n' ' ' | cut -c1-140)"
elif [ "$(printf '%s' "$recipe" | wc -c)" -gt 500 ]; then
  ok "harden apply --dry-run compiled a recipe for a LOCAL target ($(printf '%s' "$recipe" | wc -c) bytes)"
else
  ko "harden apply --dry-run produced no recipe locally" \
     "$(printf '%s' "$recipe" | tail -2 | tr '\n' ' ' | cut -c1-140)"
fi
if has '-w /etc/' "$recipe" || has '-a always,exit' "$recipe"; then
  ok "the compiled recipe carries the audit ruleset (it used to be silently empty)"
else
  ko "the compiled recipe has no audit rules" \
     "audit.rules did not reach it: this is the failure that reported success"
fi

if [ "${PAVOIS_SCENARIO_APPLY:-1}" = "1" ]; then
  before=$(asuser 'sudo auditctl -l 2>/dev/null | wc -l' | tr -dc '0-9')
  out=$(asuser "cd ~ && pavois harden apply --target local --yes --bootstrap-cinc --no-restore-point $planlocal")
  printf '%s\n' "$out" >> "$LOG"
  after=$(asuser 'sudo auditctl -l 2>/dev/null | wc -l' | tr -dc '0-9')
  if [ "${after:-0}" -gt "${before:-0}" ]; then
    ok "the local apply converged: $after audit rules loaded (was ${before:-0})"
  else
    ko "the local apply loaded no audit rules (${before:-0} -> ${after:-0})" \
       "an apply that reports success and changes nothing is exactly the defect"
  fi

  # #288, and this is the assertion that matters: the host has just been HARDENED, so the scan an
  # operator runs next, to prove the result, must still work. It did not: the converge mounts the
  # scratch directories noexec, and a --on-target scan copied its profile to /tmp and executed it
  # there, dying with `sh: 1: env: Permission denied` and exit 126. A tool that hardens a machine
  # out of its own reach has verified nothing.
  if [ -n "$VM_IP" ] && [ -f "${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}" ]; then
    out=$("$BIN" scan "tester@$VM_IP" --key "${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}" \
            --sudo --on-target --out "$work/after" 2>&1 | plain)
    printf '%s\n' "$out" >> "$LOG"
    if has 'Permission denied' "$out" || has 'exit 126' "$out"; then
      ko "--on-target cannot scan the host it just hardened (#288)" \
         "$(printf '%s' "$out" | grep -iE 'permission denied|126' | head -1 | cut -c1-140)"
    elif rx 'grade [a-e]' "$(lower "$out")"; then
      ok "--on-target still scans the host after hardening it (#288)"
    else
      ko "--on-target produced no grade on the hardened host" \
         "$(printf '%s' "$out" | tail -2 | tr '\n' ' ' | cut -c1-160)"
    fi
  fi
else
  note "the local convergence was skipped (PAVOIS_SCENARIO_APPLY=0)"
fi

say ""
say "--- 8b. remediation, applied for real, from this machine to a VM over ssh"
#
# ON A FRESH VM, because 8a hardened the previous one and the two convergences cannot share a
# machine: after a full apply, `scan --on-target` dies with exit 126 on scratch directories the
# converge mounted `noexec` (#288). The ssh leg uses --on-target, so it would be measuring the
# consequences of 8a rather than itself.
say "  a second VM, because 8a hardened the first one (#288)"
if ! provision_vm; then
  ko "could not provision a VM for the ssh transport" "the local transport's result above still stands"
  VM_IP=""
else
  install_engine || ko "could not install the engine on the second VM" "see $LOG"
fi
#
# This exists because stopping at `harden plan` is the same mistake as testing from inside the
# repository: it leaves half the product unexercised, and that half held the worst defect of the
# batch. `harden apply` read docs/reference/audit.rules and the per-OS kernel recipe under
# findRoot() WITH THE ERROR DISCARDED, so a downloaded binary converged a plan with an EMPTY audit
# ruleset and an EMPTY kernel recipe, and reported success. #286 at least stopped and said so; this
# hardened a machine, skipped two domains, and told the operator it had worked.
#
# It runs over ssh, which used to be the ONLY way `harden apply` worked (#200 fixed the local one).
# This machine is the control host, the VM is the target, which is the documented usage and keeps
# the rule that nothing hardens the workstation.
KEY=${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}
if [ -z "$VM_IP" ] || [ ! -f "$KEY" ]; then
  ko "cannot reach the VM over ssh to apply" "no address, or no key at $KEY"
else
  TARGET="tester@$VM_IP"
  planfile="$work/plan.yml"

  # --dry-run first: it COMPILES the Chef recipe and prints it without converging, which is the
  # cheapest possible proof that the embedded data reaches the recipe. If audit.rules were empty
  # again, the recipe would compile happily and say nothing, exactly as it used to.
  if "$BIN" harden plan "$TARGET" --key "$KEY" --sudo --out "$planfile" >>"$LOG" 2>&1 \
     && [ -s "$planfile" ]; then
    ok "harden plan reached the VM over ssh and wrote a plan"
  else
    ko "harden plan over ssh produced nothing" "see $LOG"
  fi

  # The SAME enable step as the local leg. Forgetting it here is how this phase asserted against a
  # recipe that was legitimately empty: a plan is born with `apply: false` on every gap, because
  # flipping them is the operator's decision, so an apply straight off a fresh plan converges
  # nothing and loads no audit rules. The assertion then reads as a product defect.
  if [ -s "$planfile" ]; then
    enabled=$(uv run --with pyyaml python3 tools/harden_plan_enable.py "$planfile" --ssh-user tester 2>&1 | tail -2)
    printf '%s\n' "$enabled" >> "$LOG"
    if rx 'enabled [0-9]+' "$enabled"; then
      ok "the plan's gaps were enabled ($(printf '%s' "$enabled" | grep -oE 'enabled [0-9]+' | head -1))"
    else
      ko "could not enable the ssh plan's gaps" "$(printf '%s' "$enabled" | tr '\n' ' ' | cut -c1-140)"
    fi
  fi

  if [ -s "$planfile" ]; then
    recipe=$("$BIN" harden apply --target "$TARGET" --key "$KEY" --sudo --yes --dry-run "$planfile" 2>&1 | plain)
    printf '%s\n' "$recipe" >> "$LOG"
    # A line every real audit ruleset carries. Its absence is the silent failure, and the only way
    # to see it is to look inside the compiled recipe rather than at the exit code.
    if has '-w /etc/' "$recipe" || has '-a always,exit' "$recipe"; then
      ok "the compiled recipe carries the audit ruleset (it used to be silently empty)"
    else
      ko "the compiled recipe has no audit rules" \
         "audit.rules did not reach it: this is the failure that reported success"
    fi
    if has 'kernel' "$(lower "$recipe")"; then
      ok "the compiled recipe knows about the kernel-build recipe"
    else
      note "no kernel-build content in the recipe (the plan may not have enabled it)"
    fi

    # And then it actually converges. One pass, not the loop to fixpoint: a single apply can never
    # close the gaps it creates (installing `at` creates /etc/at.deny, which another control wants
    # gone), so convergence is tools/harden_validate.sh's job at the slowest rung. What this proves
    # is that an apply RUNS from a downloaded binary and changes the machine.
    if [ "${PAVOIS_SCENARIO_APPLY:-1}" = "1" ]; then
      before=$(sshvm 'sudo auditctl -l 2>/dev/null | wc -l')
      if "$BIN" harden apply --target "$TARGET" --key "$KEY" --sudo --yes \
           --bootstrap-cinc --no-restore-point "$planfile" >>"$LOG" 2>&1; then
        ok "harden apply converged the VM from a binary with nothing beside it"
      else
        ko "harden apply failed" "its output is in $LOG"
      fi
      after=$(sshvm 'sudo auditctl -l 2>/dev/null | wc -l')
      if [ "${after:-0}" -gt "${before:-0}" ]; then
        ok "the target now has $after audit rules loaded (it had ${before:-0})"
      else
        ko "the target has no more audit rules than before (${before:-0} -> ${after:-0})" \
           "an apply that reports success and loads no rules is exactly the defect"
      fi
    else
      note "the convergence itself was skipped (PAVOIS_SCENARIO_APPLY=0)"
    fi
  fi
fi

say ""
if [ "$fails" -eq 0 ]; then
  say "the whole first-run scenario works on a machine that had nothing."
else
  say "$fails check(s) failed: a user would hit them on their first run."
fi
say "log: $LOG"
exit "$fails"
