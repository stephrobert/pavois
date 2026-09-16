#!/usr/bin/env bash
# Install the PUBLISHED v0.1.0 artifacts on a virgin VM of each distribution, and report what a
# first-time user actually sees.
#
# Written because of a field report: installing the RPM on AlmaLinux was said to be missing
# dependencies. That claim has to be settled by installing it on a machine that has never seen this
# project, not by reading nfpm.yaml. A build machine has Go, a scanning station has cinc-auditor, and
# both of them hide exactly the failure being reported.
#
# What it checks, in the order a user meets it:
#   1. the package manager accepts the package, and says so about dependencies
#   2. the binary is on PATH and runs                      -> `pavois version`
#   3. it is genuinely static                              -> `ldd`, `file`
#   4. what `pavois doctor` says a fresh machine is missing
#
# Point 4 is the likely answer: pavois needs CINC Auditor to SCAN, and refuses to install it behind
# your back. A user reading "no native CINC engine found" right after installing a package can
# reasonably call that a missing dependency, and the question is then whether the packaging should
# declare it, recommend it, or keep saying so at runtime.
#
# Usage: tools/release/install_matrix.sh [os...]      (default: rhel9 rhel8 fedora debian12 ubuntu2404)
# One VM at a time, destroyed at the end of each round: they run on the maintainer's own machine.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

VERSION=v0.1.0
# The version the locally built packages carry. It has to be a real version string: `pavois version`
# printing "dev" would make step 4 pass on a binary nobody could have released.
LOCAL_VERSION=${PAVOIS_LOCAL_VERSION:-0.1.1}
BASE="https://github.com/stephrobert/pavois/releases/download/${VERSION}"
KEY=${PAVOIS_SSH_KEY:-$HOME/.ssh/id_ed25519}
# The keys are tools/vm.py's, not the distribution names: `rhel9` IS images:almalinux/9/cloud,
# which is precisely the image the field report is about. Using "alma9" here fails with an
# "unknown OS" that looks like a broken script rather than a wrong name.
OSES=${*:-"rhel9 rhel8 fedora debian12 ubuntu2404"}
OUT=reports/install-matrix-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
LOG="$OUT/matrix.log"
: > "$LOG"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }

# The artifact and the install command differ per family, and so does the "what is missing" answer.
# PKG_VERSION is the published one by default, and the locally built one in local mode: a package
# named after a version its binary does not carry is a trap for whoever reads the log later.
PKG_VERSION=${VERSION#v}
[ "${PAVOIS_LOCAL_PKG:-}" = "1" ] && PKG_VERSION=$LOCAL_VERSION
artifact_for() {
  case "$1" in
    rhel8|rhel9|rhel10|fedora) echo "pavois-${PKG_VERSION}.amd64.rpm" ;;
    *)                         echo "pavois_${PKG_VERSION}_amd64.deb" ;;
  esac
}
install_cmd_for() {
  case "$1" in
    rhel8|rhel9|rhel10|fedora) echo "sudo -S -p '' dnf install -y ./PKG" ;;
    *)             echo "sudo -S -p '' apt-get install -y ./PKG" ;;
  esac
}

# With PAVOIS_LOCAL_PKG=1 the packages come from the working tree, so a fix can be validated before
# it is released. nfpm reads the binary from dist/, so the binary is built first.
LOCAL_DIST=""
if [ "${PAVOIS_LOCAL_PKG:-}" = "1" ]; then
  LOCAL_DIST=$(mktemp -d)
  trap 'rm -rf "$LOCAL_DIST"' EXIT
  echo "building the packages from the working tree"
  # The SAME flags as .github/workflows/release.yml, not `mise run build`. A plain `go build` links
  # against the build machine's libc: `file` says "dynamically linked", and the package then depends
  # on a glibc it never declares. That is a different artifact from the one that ships, so testing it
  # answers a question nobody asked.
  mkdir -p "$LOCAL_DIST/dist"
  ( cd go && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
      -ldflags="-s -w -X pavois/cmd.version=${LOCAL_VERSION}" \
      -o "$LOCAL_DIST/dist/pavois-linux-amd64" . ) \
    || { echo "go build failed" >&2; exit 1; }
  # shellcheck disable=SC2016  # ${ARCH} and ${VERSION} are nfpm's placeholders, not shell variables
  sed -e 's|${ARCH}|amd64|g' -e "s|\${VERSION}|${LOCAL_VERSION}|g" nfpm.yaml > "$LOCAL_DIST/nfpm.yaml"
  # nfpm resolves the maintainer scripts from its own working directory, so packaging/ travels with
  # the config. Leaving it behind makes nfpm exit non-zero and reads as a broken nfpm.yaml.
  cp -r packaging "$LOCAL_DIST/packaging"
  ( cd "$LOCAL_DIST" \
    && nfpm pkg --config nfpm.yaml --packager deb --target "pavois_${LOCAL_VERSION}_amd64.deb" >/dev/null \
    && nfpm pkg --config nfpm.yaml --packager rpm --target "pavois-${LOCAL_VERSION}.amd64.rpm" >/dev/null ) \
    || { echo "nfpm failed" >&2; exit 1; }
  echo "  $(find "$LOCAL_DIST" -maxdepth 1 \( -name '*.deb' -o -name '*.rpm' \) | wc -l) package(s) built"
fi

failures=0
for os in $OSES; do
  say ""
  say "================ $os"
  pkg=$(artifact_for "$os")
  install=$(install_cmd_for "$os")
  install=${install/PKG/$pkg}

  say "--- a fresh VM"
  mise run vm -- down "$os" >/dev/null 2>&1
  if ! mise run vm -- up "$os" --sudo-password "${PAVOIS_SUDO_PASSWORD:-}" >/dev/null 2>&1; then
    say "  VM creation FAILED, skipping"
    failures=$((failures + 1))
    continue
  fi
  ip=$(mise run vm -- ip "$os" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
  if [ -z "$ip" ]; then
    say "  no IP, skipping"
    failures=$((failures + 1))
    mise run vm -- down "$os" >/dev/null 2>&1
    continue
  fi
  say "  $os at $ip"

  # -F /dev/null: a global ssh_config with a `Host *` ProxyJump breaks direct connections and fails
  # with a misleading "UNKNOWN port 65535" that reads exactly like a broken VM.
  sshx() {
    ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=20 \
        -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -i "$KEY" "pavois@$ip" "$@" 2>&1
  }

  # `sudo -S` reads the password from stdin and `-p ''` silences the prompt. The password is piped,
  # never an argument: an argument is visible in `ps` and in the shell history of both machines.
  sshsudo() {
    printf '%s\n' "${PAVOIS_SUDO_PASSWORD:-}" | ssh -F /dev/null \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=20 \
      -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -i "$KEY" "pavois@$ip" "$@" 2>&1
  }

  # A test that has to "work the first time" states a verdict; it does not print a transcript and
  # leave the reading to whoever opens the log. The raw output still goes to $LOG as the evidence.
  pass() { say "  [ ok ] $1"; }
  fail() { say "  [FAIL] $1"; say "         $2"; failures=$((failures + 1)); }
  note() { say "  [note] $1"; }

  say "--- 1. the package manager, on a machine that has never seen this project"
  if [ "${PAVOIS_LOCAL_PKG:-}" = "1" ]; then
    # The working tree's packages, carried to the VM. A fix has no published release to test
    # against, and testing it here would prove nothing: this machine has the repository, the
    # engine and the toolchain, which is precisely where the failure cannot happen.
    note "local build, not the published release"
    # Piped through ssh, not scp: since OpenSSH 9 scp speaks SFTP, and these cloud images ship no
    # sftp-server subsystem. The failure reads "subsystem request failed on channel 0", which looks
    # like a broken VM rather than a missing subsystem. `cat` needs nothing but a shell.
    if ! sshx "cat > '$pkg'" < "$LOCAL_DIST/$pkg"; then
      fail "could not copy $pkg to the VM" "the VM answered, but the transfer did not complete"
      mise run vm -- down "$os" >/dev/null 2>&1
      continue
    fi
    sshx "cat > sample.json" < docs/examples/after.json || true
  else
    sshx "curl -fsSLO '$BASE/$pkg'" >/dev/null
    sshx "curl -fsSLO 'https://raw.githubusercontent.com/stephrobert/pavois/main/docs/examples/after.json' -o sample.json" >/dev/null
  fi

  out=$(sshsudo "$install; echo \"rc=\$?\"")
  printf '%s\n' "$out" >> "$LOG"
  if printf '%s' "$out" | grep -q 'rc=0'; then
    pass "the package installs, and the manager asks for nothing else"
    # The engine is a runtime dependency no package manager can fetch (CINC Auditor is in no distro
    # repository). Since it cannot be declared, it has to be said, at the one moment the user is
    # reading the terminal. A field report called its absence "missing dependencies".
    # Three spellings, because dnf5 prefixes scriptlet output with ">>> " and truncates each line at
    # the terminal width: `cinc-auditor` came back as `cinc-a` on Fedora while the message was
    # perfectly present. Matching one exact token would make this check a measure of column count.
    if printf '%s' "$out" | grep -qiE 'cinc.auditor|omnitruck|pavois doctor'; then
      pass "the install tells the user CINC Auditor is needed to scan"
    else
      fail "the install says nothing about the scan engine" \
           "packaging/postinstall.sh did not run: the first scan becomes the messenger"
    fi
  else
    fail "the package manager refused the package" \
         "$(printf '%s' "$out" | grep -iE 'requires|conflict|nothing provides|Error' | head -2 | tr '\n' ' ')"
    mise run vm -- down "$os" >/dev/null 2>&1
    continue
  fi

  say "--- 2. what the package DECLARES it needs"
  case "$os" in
    rhel*|fedora) deps=$(sshx "rpm -qpR $pkg 2>/dev/null | grep -v '^rpmlib' | sort -u") ;;
    *)            deps=$(sshx "dpkg-deb -f $pkg Depends Pre-Depends Recommends 2>/dev/null") ;;
  esac
  printf '%s\n' "$deps" >> "$LOG"
  if [ -n "$(printf '%s' "$deps" | tr -d '[:space:]')" ]; then
    note "declares: $(printf '%s' "$deps" | tr '\n' ' ' | cut -c1-90)"
  else
    note "declares nothing (a static binary has no library to ask for)"
  fi

  say "--- 3. did the files land, and is the binary self-contained"
  # `ldd` and not `file`: the Debian and Ubuntu cloud images ship no `file`, and "command not found"
  # was being counted as a dynamically linked binary. The harness was measuring its own gap on two
  # of five distributions, on the very same binary the other three had just certified static.
  # ldd comes with the C library, so it is on every one of these machines.
  kind=$(sshx "ldd /usr/bin/pavois 2>&1 || true")
  printf '%s\n' "$kind" >> "$LOG"
  if printf '%s' "$kind" | grep -qE 'not a dynamic executable|statically linked'; then
    pass "/usr/bin/pavois is a static binary (no libc to be missing)"
  elif printf '%s' "$kind" | grep -q 'command not found'; then
    fail "cannot tell whether /usr/bin/pavois is static" "neither ldd nor file on this image"
  else
    # This is the shape a "missing dependencies" report takes: a dynamically linked binary whose
    # package declares no library, which loads on the build machine and dies on an older one.
    fail "/usr/bin/pavois is dynamically linked" \
         "$(printf '%s' "$kind" | tr '\n' ' ' | cut -c1-90). Build with CGO_ENABLED=0, as release.yml does"
  fi

  say "--- 4. does it run"
  # The whole output, not its first lines: `pavois version` opens with an ASCII banner, so `head -3`
  # returned the banner and the check failed on all five machines while the package was correct.
  ver=$(sshx "pavois version 2>&1")
  printf '%s\n' "$ver" >> "$LOG"
  if printf '%s' "$ver" | grep -qF "$PKG_VERSION"; then
    pass "pavois version reports $PKG_VERSION"
  else
    fail "pavois version does not report $PKG_VERSION" \
         "got: $(printf '%s' "$ver" | grep -iE '^ *pavois ' | tr '\n' ' ' | cut -c1-80)"
  fi

  say "--- 5. does it do its job on a machine that has only this package"
  # The v0.1.0 defect, exactly: the corpus was compiled in and the lookup asked the filesystem, so
  # every machine that was not a checkout listed nothing and resolved nothing.
  listed=$(sshx "pavois profiles 2>&1" | grep -cE '^ +linux/')
  if [ "${listed:-0}" -ge 5 ]; then
    pass "the embedded corpus is visible: $listed profiles"
  else
    fail "pavois profiles lists $listed profile(s) on a fresh machine" \
         "this is how v0.1.0 shipped: embedded corpus, filesystem lookup"
  fi
  # Replaying an archived report resolves a profile and grades WITHOUT an engine, so this separates
  # "the rules are reachable" from "CINC is installed". They are different failures with different
  # fixes, and the field report confused them.
  replay=$(sshx "pavois scan local --from sample.json --out . 2>&1 | tail -20")
  printf '%s\n' "$replay" >> "$LOG"
  if printf '%s' "$replay" | grep -q 'no bundled profile'; then
    fail "no profile resolves for this platform" \
         "$(printf '%s' "$replay" | grep 'no bundled profile' | head -1)"
  elif printf '%s' "$replay" | grep -qE 'grade [A-E]'; then
    pass "a scan resolves a profile and grades ($(printf '%s' "$replay" | grep -oE 'grade [A-E]' | head -1))"
  else
    fail "the scan produced no grade" "$(printf '%s' "$replay" | tail -2 | tr '\n' ' ' | cut -c1-120)"
  fi

  say "--- 6. and what a first scan actually tells this user"
  # Not an assertion: pavois needs CINC Auditor to READ a host, and refuses to install it behind
  # your back. This records the sentence the user meets, because that sentence is what gets reported
  # as "missing dependencies".
  sshsudo "pavois scan local --sudo 2>&1 | grep -iE 'error|engine' | head -3" \
    | grep -viE '^[[:space:]]*$|\[sudo\]' | sed 's/^/  /' | tee -a "$LOG"

  mise run vm -- down "$os" >/dev/null 2>&1
  say "  VM destroyed"
done

say ""
if [ "$failures" -eq 0 ]; then
  say "every distribution installed the package and ran a graded scan from it."
else
  say "$failures check(s) failed: these artifacts would ship broken."
fi
say "log: $LOG"
exit "$failures"
