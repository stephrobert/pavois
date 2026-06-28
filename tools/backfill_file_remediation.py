#!/usr/bin/env python3
"""Derive the missing `file` remediation for File-ownership AND File-permissions controls
from their check — the check fully determines the fix, so no manual authoring.

  - File ownership: path from file('X'), owner/group from its('uid'/'gid') { should eq N }.
  - File permissions: path from file('X'); the target MODE is the most-permissive mode that
    still satisfies every `should_not be_<perm>.by('<who>')` clause (start at 0777, clear each
    forbidden bit). e.g. /etc/shadow -> 0640, /etc/passwd -> 0644. Setting that mode also
    clears any setuid/setgid/sticky the clauses forbid.

  tools/backfill_file_remediation.py [<os>] [--apply]     # default os: debian12

Only touches controls with remediation: null whose uid/gid map to a known system account.
Recursive directory checks (no single file('X')) are skipped and reported.
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
OS = next((a for a in sys.argv[1:] if not a.startswith("-")), "debian12")
APPLY = "--apply" in sys.argv
F = ROOT / "docs" / "reference" / "pavois-content" / f"{OS}.yml"

UID = {"0": "root"}
GID = {"0": "root", "4": "adm", "42": "shadow"}  # debian-family system groups (RHEL only uses 0)
PERM = {
    ("executable", "owner"): 0o100, ("writable", "owner"): 0o200, ("readable", "owner"): 0o400,
    ("executable", "group"): 0o010, ("writable", "group"): 0o020, ("readable", "group"): 0o040,
    ("executable", "other"): 0o001, ("writable", "other"): 0o002, ("readable", "other"): 0o004,
}

ref = yaml.safe_load(F.read_text())["rules"]
targets, skipped, nperm, nown = {}, [], 0, 0
for cid, e in ref.items():
    dom = str(e.get("domain"))
    if e.get("remediation") or dom not in ("File ownership", "File permissions"):
        continue
    chk = "\n".join(e.get("check") or [])
    pm = re.search(r"file\('([^']+)'\)", chk)
    if not pm:
        skipped.append((cid, "no single path")); continue
    block = ["    remediation:", f"      path: {pm.group(1)}", "      resource: file"]
    if dom == "File ownership":
        uid = re.search(r"its\('uid'\)\s*\{\s*should eq (\d+)", chk)
        gid = re.search(r"its\('gid'\)\s*\{\s*should eq (\d+)", chk)
        if not (uid or gid):
            skipped.append((cid, "no uid/gid")); continue
        bad = None
        if uid:
            bad = "uid " + uid.group(1) if uid.group(1) not in UID else None
            if not bad:
                block.append(f"      owner: {UID[uid.group(1)]}")
        if gid and not bad:
            bad = "gid " + gid.group(1) if gid.group(1) not in GID else None
            if not bad:
                block.append(f"      group: {GID[gid.group(1)]}")
        if bad:
            skipped.append((cid, bad)); continue
        nown += 1
    else:  # File permissions: max-allowed mode from the should_not clauses
        clauses = re.findall(r"should_not be_(executable|writable|readable)\.by\('(owner|group|other)'\)", chk)
        if not clauses:
            skipped.append((cid, "no perm clauses")); continue
        mode = 0o777
        for perm, who in clauses:
            mode &= ~PERM[(perm, who)]
        block.append(f"      mode: '{mode:04o}'")
        nperm += 1
    targets[cid] = block

lines = F.read_text().split("\n")
out, i, cur, applied = [], 0, None, 0
while i < len(lines):
    ln = lines[i]
    m = re.match(r"^  ([a-z0-9][a-z0-9_-]*):$", ln)
    if m:
        cur = m.group(1)
    if cur in targets and ln == "    remediation: null":
        out.extend(targets.pop(cur)); applied += 1; i += 1; continue
    out.append(ln); i += 1

text = "\n".join(out)
yaml.safe_load(text)  # validate before writing
print(f"{OS}: {applied} derived ({nown} ownership + {nperm} permissions), {len(skipped)} skipped")
for c, r in skipped[:8]:
    print(f"  skip {c}  ({r})")
if APPLY:
    F.write_text(text)
    print("APPLIED")
