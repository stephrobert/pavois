#!/usr/bin/env bash
# What does `Defaults noexec` in sudoers ACTUALLY break, and does a scoped carve-out fix it? (#288)
#
# The control `sudo-noexec` (SSG sudo_add_noexec, ANSSI BP-028 R39) writes `Defaults noexec` into
# sudoers, which makes sudo preload a library blocking exec*() in whatever it runs. It broke pavois,
# whose elevation is `sudo sh -c '…'`, and the open question was whether it also breaks ORDINARY
# administration. It does: `sudo apt-get install` fails.
#
# That question decides something the rule base cannot decide by opinion, so it is measured rather
# than argued: a fresh VM, the sudoers lines, and commands an operator actually runs. No full
# harden, because a converge changes a hundred other things and the answer would be about all of
# them at once.
#
# Three configurations, on the same machine, so the comparison is against itself:
#   1. plain sudoers
#   2. `Defaults noexec`, which is what the control's remediation writes today
#   3. the same plus a Cmnd_Alias carve-out for the package managers
#
# Usage: tools/release/measure_sudo_noexec.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

VM=pavois-noexec-probe
# A scratch dir on THIS machine for the probe profile, pushed to the VM rather than typed into it.
work_probe=$(mktemp -d)
say() { printf '%s\n' "$*"; }
cleanup() { incus delete "$VM" --force >/dev/null 2>&1; rm -rf "$work_probe"; say "VM deleted"; }
trap cleanup EXIT INT TERM

say "== a fresh VM"
incus delete "$VM" --force >/dev/null 2>&1
incus init images:ubuntu/24.04 "$VM" --vm -c limits.cpu=2 -c limits.memory=2GiB >/dev/null 2>&1 \
  || { say "could not create the VM"; exit 1; }
incus config device add "$VM" eth0 nic network=incusbr0 >/dev/null 2>&1
incus start "$VM" >/dev/null 2>&1 || { say "could not start the VM"; exit 1; }
for _ in $(seq 1 72); do incus exec "$VM" -- true >/dev/null 2>&1 && break; sleep 5; done
incus exec "$VM" -- true >/dev/null 2>&1 || { say "the agent never answered"; exit 1; }

vmsh() { incus exec "$VM" -- bash -lc "$1" 2>&1; }
asuser() { incus exec "$VM" -- su - tester -c "$1" 2>&1; }

vmsh 'id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester' >/dev/null
vmsh 'echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester && chmod 0440 /etc/sudoers.d/tester' >/dev/null
vmsh 'apt-get update -qq' >/dev/null 2>&1
say "  up"

probes=(
  'sudo apt-get install -y -qq sl'
  'sudo systemctl restart cron'
  'sudo bash -c "echo hello"'
  'sudo sh -c "env HOME=/tmp true"'
  'sudo -i true'
  'sudo /usr/bin/id -u'
)

run_all() {
  for p in "${probes[@]}"; do
    if out=$(asuser "$p" 2>&1); then
      printf '  %-40s ok\n' "${p:0:40}"
    else
      printf '  %-40s FAIL  %s\n' "${p:0:40}" "$(printf '%s' "$out" | tail -1 | cut -c1-64)"
    fi
  done
  # The control's own check, verbatim from the rule base: a grep for a Defaults ... noexec line.
  # WITH sudo: /etc/sudoers is 0440 root:root, so an unprivileged grep cannot read it and the
  # control reported "fails" in every configuration, including the one that satisfies it. The
  # control genuinely needs root to be evaluated, which is worth knowing on its own.
  if asuser "sudo grep -rqE '^[^#]*Defaults[^#]*\bnoexec\b' /etc/sudoers /etc/sudoers.d/ 2>/dev/null" >/dev/null 2>&1; then
    printf '  %-40s PASSES\n' "the control sudo-noexec"
  else
    printf '  %-40s fails\n' "the control sudo-noexec"
  fi
}

say ""
say "== 1. plain sudoers"
run_all
vmsh 'apt-get remove -y -qq sl' >/dev/null 2>&1

say ""
say "== 2. the remediation as the rule base writes it today"
vmsh 'printf "Defaults noexec\n" > /etc/sudoers.d/99-pavois-noexec && chmod 0440 /etc/sudoers.d/99-pavois-noexec && visudo -cf /etc/sudoers.d/99-pavois-noexec'
run_all
vmsh 'apt-get remove -y -qq sl' >/dev/null 2>&1

say ""
say "== 3. the same, with a carve-out for the package managers"
# Written to a FILE on the VM rather than echoed through three layers of quoting: the continuation
# backslashes and the alias syntax do not survive an incus exec + su -c round trip.
cat > /tmp/pavois-noexec-scoped <<'SUDOERS'
# Global hardening
Defaults noexec

# Commands that legitimately have to execute sub-processes
Cmnd_Alias PAVOIS_PACKAGE_MANAGERS = \
    /usr/bin/apt, \
    /usr/bin/apt-get, \
    /usr/bin/dpkg

Defaults!PAVOIS_PACKAGE_MANAGERS !noexec
SUDOERS
incus file push /tmp/pavois-noexec-scoped "$VM/etc/sudoers.d/99-pavois-noexec" >/dev/null 2>&1
rm -f /tmp/pavois-noexec-scoped
vmsh 'chmod 0440 /etc/sudoers.d/99-pavois-noexec && chown root:root /etc/sudoers.d/99-pavois-noexec'
say "  visudo says: $(vmsh 'visudo -cf /etc/sudoers.d/99-pavois-noexec' | tail -1)"
run_all

say ""
say "== does noexec still stop a shell escape from an editor or a pager"
# This is what the control is FOR: the sudoers manual names vi and more as the typical case. A
# measurement that only shows apt surviving says nothing about whether the control still works.
vmsh 'command -v vim >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vim less' >/dev/null 2>&1

# The escape has to leave EVIDENCE. An editor exits 0 whether or not its `!` succeeded, so a probe
# keyed on the exit code reports whatever the editor felt like returning: the first version of this
# said "the control is NOT doing its job" without having measured anything.
escaped() { # <label> <command that attempts the escape>
  vmsh 'rm -f /tmp/pavois-escaped' >/dev/null 2>&1
  asuser "$2" >/dev/null 2>&1
  if vmsh 'test -f /tmp/pavois-escaped && echo yes' | grep -q yes; then
    say "  $1 SHELLED OUT under sudo: the control is not stopping it"
  else
    say "  $1 could not shell out under sudo: the control holds"
  fi
  vmsh 'rm -f /tmp/pavois-escaped' >/dev/null 2>&1
}

escaped "vi  " 'sudo vim -Es -c "!/bin/touch /tmp/pavois-escaped" -c q /etc/hostname'
escaped "less" 'echo q | sudo less +"!/bin/touch /tmp/pavois-escaped" /etc/hostname'
# And the control group: the same escape with noexec OFF for that command must succeed, or the
# probe is measuring something other than noexec (a missing binary, a refused option, a typo).
vmsh 'printf "Defaults noexec\nDefaults!/usr/bin/vim !noexec\n" > /etc/sudoers.d/98-probe-control && chmod 0440 /etc/sudoers.d/98-probe-control' >/dev/null 2>&1
escaped "vi (noexec off for vim, control group)" 'sudo vim -Es -c "!/bin/touch /tmp/pavois-escaped" -c q /etc/hostname'
vmsh 'rm -f /etc/sudoers.d/98-probe-control' >/dev/null 2>&1

say ""
say "== can an AUDIT ENGINE run at all under noexec"
# The decisive one. I claimed `sudo <binary>` directly was enough, from /usr/bin/id, which execs
# nothing. noexec is an LD_PRELOAD inherited by descendants, and an effective-config scan exists to
# execute commands. So the question is not how pavois elevates; it is whether the scan can happen.
vmsh 'command -v cinc-auditor >/dev/null || (curl -fsSL "$(curl -fsSL "https://omnitruck.cinc.sh/stable/cinc-auditor/metadata?p=ubuntu&pv=24.04&m=x86_64" | awk "/^url/ {print \$2}")" -o /tmp/c.deb && dpkg -i /tmp/c.deb)' >/dev/null 2>&1
say "  cinc-auditor: $(vmsh 'cinc-auditor version 2>/dev/null | tail -1')"

# A one-control profile whose check EXECUTES something, which is what every pavois control does.
#
# Written HERE and pushed, not assembled with printf and escaped quotes through incus exec and
# `su -c`: the first version did that, the profile came out malformed, and the engine then failed
# in ALL THREE configurations including the control group. The measurement said BLOCKED and had
# measured nothing.
mkdir -p "$work_probe/probe-profile/controls"
cat > "$work_probe/probe-profile/inspec.yml" <<'YML'
name: probe
title: does the engine get to execute anything
version: 0.1.0
YML
cat > "$work_probe/probe-profile/controls/p.rb" <<'RB'
control 'engine-can-exec' do
  impact 1.0
  title 'the engine can run a command, which is what auditing effective config means'
  describe command('id -u') do
    its('exit_status') { should cmp 0 }
  end
end
RB
vmsh 'rm -rf /opt/probe-profile' >/dev/null 2>&1
incus file push -r "$work_probe/probe-profile" "$VM/opt/" >/dev/null 2>&1
say "  profile pushed: $(vmsh 'ls /opt/probe-profile/controls/ 2>&1 | tr "\n" " "')"

probe_engine() { # <label>
  out=$(asuser 'sudo cinc-auditor exec /opt/probe-profile -t local:// --no-create-lockfile --chef-license accept-silent 2>&1' || true)
  if printf '%s' "$out" | grep -qiE 'permission denied|not executable'; then
    say "  $1: BLOCKED  ($(printf '%s' "$out" | grep -iE 'permission denied|not executable' | head -1 | cut -c1-60))"
  elif printf '%s' "$out" | grep -qiE '1 successful|Profile Summary'; then
    say "  $1: runs"
  else
    say "  $1: unclear  ($(printf '%s' "$out" | tail -1 | cut -c1-70))"
  fi
}

probe_engine "with the package carve-out in place"

vmsh 'printf "Defaults noexec\n" > /etc/sudoers.d/99-pavois-noexec && chmod 0440 /etc/sudoers.d/99-pavois-noexec' >/dev/null
probe_engine "with a bare global noexec      "

vmsh 'rm -f /etc/sudoers.d/99-pavois-noexec' >/dev/null
probe_engine "with no noexec at all          "

say ""
say "== does the carve-out hand back a shell escape"
# The point of noexec is to stop a sudo-granted command from spawning a shell. apt-get can be told
# to run one: if this works, the carve-out has re-opened exactly the door the control closes, and
# that matters for a RESTRICTED sudo grant even though it is moot for an admin who already has ALL.
if asuser 'sudo apt-get -o "APT::Update::Pre-Invoke::=/bin/true" update' >/dev/null 2>&1; then
  say "  apt-get can still run an arbitrary command through Pre-Invoke: the carve-out reopens it"
else
  say "  apt-get Pre-Invoke refused: the carve-out does not reopen that path"
fi
