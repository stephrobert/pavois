#!/usr/bin/env bash
# Pavois: phantom-package detector.
#
# A `pkg-<x>-removed` control that names a package the distribution does not HAVE always passes
# and proves NOTHING (dpkg/rpm simply answers "not installed"). A `pkg-<x>-installed` control that
# names a phantom is the mirror image: a permanent, unfixable FAIL. Both were in the corpus: the
# debian columns carried RHEL names (httpd, bind, gdm, dovecot, tftp-server...) while the ubuntu
# columns of the SAME controls were right, and el10 kept auditing packages its repos dropped (abrt,
# xinetd, ypserv). This is the check that catches them, and it needs the real distribution: no
# static lint can know what `apt` or `dnf` actually has.
#
# Usage: tools/audit_packages.sh <os> <user@host> [ssh_key]
set -euo pipefail
OS="${1:?os (e.g. debian12)}"; TARGET="${2:?user@host}"; KEY="${3:-$HOME/.ssh/id_ed25519}"
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $KEY"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# every package name the corpus audits for this OS
uv run --with pyyaml python3 - "$ROOT/docs/reference/pavois-content/$OS.yml" <<'EOF' > /tmp/pavois-pkgs.$$
import re, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))["rules"]
names = set()
for cid, v in d.items():
    t = v.get("template") or {}
    if t.get("name") == "package" and t.get("package"):
        names.add(t["package"])
        continue
    for ln in v.get("check") or []:
        m = re.search(r"package\('([^']+)'\)", ln)
        if m:
            names.add(m.group(1))
print(" ".join(sorted(names)))
EOF

echo "== $OS: checking $(wc -w < /tmp/pavois-pkgs.$$) audited package names against $TARGET"
$SSH "$TARGET" 'if command -v apt-cache >/dev/null 2>&1; then
    for p in $(cat); do c=$(apt-cache policy "$p" 2>/dev/null | grep -m1 Candidate: | awk "{print \$2}");
      [ -n "$c" ] && [ "$c" != "(none)" ] || echo "  PHANTOM: $p"; done
  else
    for p in $(cat); do dnf -q list --available "$p" >/dev/null 2>&1 || dnf -q list --installed "$p" >/dev/null 2>&1 || echo "  PHANTOM: $p"; done
  fi' < /tmp/pavois-pkgs.$$ | tee /tmp/pavois-phantoms.$$
rm -f /tmp/pavois-pkgs.$$
n=$(grep -c PHANTOM /tmp/pavois-phantoms.$$ || true); rm -f /tmp/pavois-phantoms.$$
[ "$n" -eq 0 ] && { echo "OK: every audited package exists on $OS"; exit 0; }
echo "FAIL: $n audited package(s) do not exist on $OS: those controls prove nothing"
exit 1
