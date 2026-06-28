#!/usr/bin/env python3
"""Regression harness for pavois's "tricky" rules — the ones whose verdict depends on the
active standard (per-norm thresholds via input('pavois_standard')). cinc-auditor has no
built-in unit test for that logic, so we drive it as an INTEGRATION matrix:

    set a fixture value on the target  ->  scan with each --standard  ->  assert pass/fail.

Usage: tools/test-rules.py <user@host> [--key <key>]
Run against a THROWAWAY target (Incus/Outscale VM), never master1 — it mutates config.
"""
import json
import subprocess
import sys
import glob
import os

TARGET = sys.argv[1]
KEY = sys.argv[sys.argv.index("--key") + 1] if "--key" in sys.argv else os.path.expanduser("~/.ssh/id_ed25519")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def ssh(cmd):
    subprocess.run(["ssh", "-tt", "-F", "/dev/null", "-i", KEY, "-o", "StrictHostKeyChecking=no",
                    TARGET, cmd], capture_output=True, text=True)


def scan_status(control, standard):
    args = [f"{ROOT}/go/pavois", "scan", TARGET, "--key", KEY, "--sudo", "--on-target", "-f", "json"]
    if standard:
        args += ["--standard", standard]
    subprocess.run(args, capture_output=True, text=True)
    rep = max(glob.glob(f"{ROOT}/reports/rapport-*.json"), key=os.path.getmtime)
    d = json.load(open(rep))
    for p in d["profiles"]:
        for c in p["controls"]:
            if c["id"] == control and c["results"]:
                return c["results"][0].get("status")
    return "absent"


# (description, setup-command, control, standard, expected) — extend with more tricky rules.
CASES = [
    ("pass_min_len=13 satisfies nist (>=12)",        r"sudo sed -ri 's/^PASS_MIN_LEN.*/PASS_MIN_LEN\t13/' /etc/login.defs", "logindefs-pass_min_len", "nist", "passed"),
    ("pass_min_len=13 fails bp28 (>=15)",            r"sudo sed -ri 's/^PASS_MIN_LEN.*/PASS_MIN_LEN\t13/' /etc/login.defs", "logindefs-pass_min_len", "bp28", "failed"),
    ("pass_min_len=13 fails default (most secure)",  r"sudo sed -ri 's/^PASS_MIN_LEN.*/PASS_MIN_LEN\t13/' /etc/login.defs", "logindefs-pass_min_len", "",     "failed"),
    ("pass_min_len=15 satisfies bp28",               r"sudo sed -ri 's/^PASS_MIN_LEN.*/PASS_MIN_LEN\t15/' /etc/login.defs", "logindefs-pass_min_len", "bp28", "passed"),
    ("pass_min_len=11 fails nist",                   r"sudo sed -ri 's/^PASS_MIN_LEN.*/PASS_MIN_LEN\t11/' /etc/login.defs", "logindefs-pass_min_len", "nist", "failed"),
]

print(f"pavois rule tests on {TARGET}\n")
ok = 0
for desc, setup, ctrl, std, expected in CASES:
    ssh(setup)
    got = scan_status(ctrl, std)
    p = got == expected
    ok += p
    print(f"  [{'PASS' if p else 'FAIL'}] {desc}  (--standard {std or '_default'}: {got}, expected {expected})")
ssh(r"sudo sed -ri 's/^PASS_MIN_LEN.*/PASS_MIN_LEN\t15/' /etc/login.defs")  # restore
print(f"\n{ok}/{len(CASES)} passed")
sys.exit(0 if ok == len(CASES) else 1)
