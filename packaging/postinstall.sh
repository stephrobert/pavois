#!/bin/sh
# Printed by dpkg/rpm right after the files land.
#
# Written because of a field report: "installing the RPM on AlmaLinux, dependencies are missing".
# They are not. The binary is static, the package declares nothing and needs nothing, and
# `dnf install` returns 0 without a word. What the user actually met was the first scan:
#
#     error: could not reach or identify local: no native CINC engine found
#
# CINC Auditor is a RUNTIME dependency, and it cannot be declared: it is in no distribution
# repository, it installs from omnitruck. So the package cannot pull it, and pavois will not install
# it behind your back. The one thing the package can do is say so at the moment the user is looking.
#
# It points at the documentation rather than printing the omnitruck one-liner, which is a script
# piped into a root shell. A hardening tool does not ask for that, and the installation page has the
# room to give the verified download properly: fetch the package URL and its published sha256, check
# the sum, install with the system package manager.
#
# Every line stays under 72 columns. dnf5 prefixes scriptlet output with ">>> " and TRUNCATES each
# line at the terminal width, so a longer line reaches a Fedora user cut off mid-word, which is
# worse than saying nothing: it cannot be copied and it cannot be read.
set -e

cat <<'EOF'

pavois is installed. Nothing is missing from this package: the binary is
static and the rule corpus is already inside it.

To SCAN, one more thing is needed, and no package manager can fetch it:
CINC Auditor, the engine, is in no distribution repository.

  Install it (download, verify the checksum, then install):

    https://pavois.dev/en/installation/#engine

  Then check this host is ready:

    pavois doctor

Without the engine, the first scan stops on:
  error: no native CINC engine found

EOF
