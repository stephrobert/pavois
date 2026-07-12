#!/usr/bin/env python3
"""Focus mode: the single-OS view, scoped to what you are actually working on.

The maintainer's need is real: working on rhel10 should not mean navigating 42 000 lines of
multi-OS YAML. But a per-OS SOURCE is exactly what produced every bug of this campaign (RHEL
package names sitting in the debian columns, RHEL systemd units on Debian, 123 rhel10 controls
with no remediation, a guard on debian and not on rhel): a per-OS file cannot represent SHARING,
so it cannot protect it. And `gen.py invert` re-derives sharing by value equality, so it cannot
tell "I forked on purpose" from "I typed the wrong thing".

So: per-OS to READ, never to STORE. This prints the slice you asked for, and prints next to each
value its BLAST RADIUS — the thing a per-OS file can never show you:

    [shared:9]        this exact value is shared by 9 OSes: changing it changes THEM ALL
    [os:rhel10]       already specific to rhel10: yours alone
    [prim:pkg.httpd]  comes from the primitive table -> edit docs/reference/os/rhel10.yml

Usage:
  tools/focus.py rhel10 --failing [--from-scan reports/x.json]   the last scan's failures
  tools/focus.py rhel10 --domain Packages                        one domain
  tools/focus.py rhel10 --control ssh-permitrootlogin            one control
  tools/focus.py rhel10 --diff rhel9                             what differs between two OSes
"""

import argparse
import glob
import json
import os as _os
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
RULES = ROOT / "docs" / "reference" / "rules.yml"
CONTENT = ROOT / "docs" / "reference" / "pavois-content"

C = {
    "dim": "\033[2m",
    "b": "\033[1m",
    "red": "\033[31m",
    "grn": "\033[32m",
    "yel": "\033[33m",
    "cyn": "\033[36m",
    "0": "\033[0m",
}
if not sys.stdout.isatty():
    C = dict.fromkeys(C, "")


def radius(entry, field, os_):
    """Who else does this value belong to? That is the question a per-OS file cannot ask."""
    v = entry.get(field)
    if isinstance(v, dict) and "@os" in v:
        mine = v["@os"].get(os_, v.get("default"))
        same = [o for o, x in v["@os"].items() if x == mine]
        if len(same) == 1:
            return f"{C['yel']}[os:{os_}]{C['0']}"
        return f"{C['red']}[shared:{len(same)}]{C['0']} {C['dim']}{','.join(sorted(same))}{C['0']}"
    n = len(entry.get("applicable_os") or [])
    return f"{C['red']}[shared:{n}]{C['0']} {C['dim']}changing it changes all {n}{C['0']}"


def primitives(text):
    out = []
    for tok in ("@{",):
        i = 0
        while (i := text.find(tok, i)) != -1:
            j = text.find("}", i)
            out.append(text[i + 2 : j])
            i = j
    return out


def show(cid, entry, os_, prof):
    oses = entry.get("applicable_os") or []
    print(f"\n{C['b']}{cid}{C['0']}  {C['dim']}applies to {len(oses)}/9{C['0']}")
    for field in ("title", "severity", "template", "check", "remediation", "danger", "waiver"):
        if field not in entry:
            continue
        v = entry[field]
        if isinstance(v, dict) and "@os" in v:
            v = v["@os"].get(os_, v.get("default"))
        if v is None:
            continue
        txt = v if isinstance(v, str) else yaml.safe_dump(v, width=100, allow_unicode=True).rstrip()
        head = txt.splitlines()
        print(f"  {C['cyn']}{field}{C['0']}: {head[0][:90]}   {radius(entry, field, os_)}")
        for ln in head[1:8]:
            print(f"      {C['dim']}{ln[:100]}{C['0']}")
        for p in primitives(txt):
            val = prof
            for part in p.split("."):
                val = (val or {}).get(part) if isinstance(val, dict) else None
            print(
                f"      {C['grn']}[prim:{p}]{C['0']} = {val!r}  "
                f"{C['dim']}edit docs/reference/os/{os_}.yml, not the rule{C['0']}"
            )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("os")
    ap.add_argument("--failing", action="store_true", help="only what failed in the last scan")
    ap.add_argument("--from-scan", help="a scan JSON (default: the newest report)")
    ap.add_argument("--domain")
    ap.add_argument("--control")
    ap.add_argument("--diff", help="another OS: show what differs between the two")
    a = ap.parse_args()

    d = yaml.safe_load(RULES.read_text())
    lib = {
        k: v for k, v in d.items() if isinstance(v, dict) and a.os in (v.get("applicable_os") or [])
    }
    pf = ROOT / "docs" / "reference" / "os" / f"{a.os}.yml"
    prof = yaml.safe_load(pf.read_text()) if pf.exists() else {}

    if a.diff:
        other = a.diff
        print(f"{C['b']}what differs between {a.os} and {other}{C['0']}")
        n = 0
        for cid, e in sorted(lib.items()):
            if other not in (e.get("applicable_os") or []):
                print(f"  {C['yel']}{cid}{C['0']}: applies to {a.os}, NOT to {other}")
                n += 1
                continue
            for f in ("check", "template", "remediation", "levels"):
                v = e.get(f)
                if isinstance(v, dict) and "@os" in v:
                    x, y = (
                        v["@os"].get(a.os, v.get("default")),
                        v["@os"].get(other, v.get("default")),
                    )
                    if x != y:
                        a1, b1 = str(x)[:38], str(y)[:38]
                        print(f"  {C['cyn']}{cid}.{f}{C['0']}: {a.os}={a1} | {other}={b1}")
                        n += 1
        print(f"\n{n} difference(s)")
        return

    want = set(lib)
    if a.control:
        if a.control not in lib:
            sys.exit(f"{a.control}: not applicable to {a.os} (or unknown)")
        want = {a.control}
    if a.domain:
        want = {c for c in want if (lib[c].get("domain") or "") == a.domain}
    if a.failing:
        p = a.from_scan or max(glob.glob(str(ROOT / "reports" / "*.json")), key=_os.path.getmtime)
        rep = json.loads(Path(p).read_text())
        failed = {
            c["id"]
            for prof_ in rep.get("profiles", [])
            for c in prof_.get("controls", [])
            if any(r.get("status") == "failed" for r in c.get("results", []))
        }
        want &= failed
        msg = f"scan: {Path(p).name} — {len(failed)} failing, {len(want)} here"
        print(f"{C['dim']}{msg}{C['0']}")

    print(f"{C['b']}FOCUS {a.os}{C['0']} — {len(want)} control(s) of {len(lib)}")
    print(
        f"{C['dim']}read-only. The blast radius is printed next to each value: a {C['0']}"
        f"{C['red']}[shared:N]{C['0']}{C['dim']} value belongs to N OSes.{C['0']}"
    )
    for cid in sorted(want):
        show(cid, lib[cid], a.os, prof)


if __name__ == "__main__":
    main()
