#!/usr/bin/env python3
"""PROTOTYPE: prove pavois's per-OS reference files can be a DRY single source.

invert  : 8 docs/reference/pavois-content/<os>.yml  ->  one per-id library (shared fields +
          values keyed @os only where they actually differ).
generate: that library  ->  the 8 per-OS rule dicts.
verify  : generated == original (semantically), per control. 100% means zero data loss and the
          per-OS files can become GENERATED artifacts, the library the source.

  tools/dry_prototype.py            # invert + generate in memory + report round-trip fidelity
  tools/dry_prototype.py --write    # also write the library to docs/reference/rules-dry.yml
"""
import glob
import json
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "docs" / "reference" / "pavois-content"
OSES = sorted(p.stem for p in REF.glob("*.yml"))
DATA = {os: yaml.safe_load((REF / f"{os}.yml").read_text())["rules"] for os in OSES}

IDS = set()
for os in OSES:
    IDS.update(DATA[os])

SCALAR = ["check", "domain", "severity", "impact", "title", "remediation", "ssg", "levels"]
NORMS = ["bp28", "nist", "pci-dss", "cis", "stig"]


def canon(v):
    """Order-insensitive key: lists compare as sets so a union written in a different order
    on each OS still counts as 'shared'."""
    if isinstance(v, list):
        return json.dumps(sorted(json.dumps(x, sort_keys=True) for x in v))
    return json.dumps(v, sort_keys=True)


def shared_or_keyed(vals_by_os, present):
    """vals_by_os: {os: value} (only OSes where the field is set). Returns ('shared', v) if every
    present OS has the same value, else ('keyed', {os: v})."""
    if len(vals_by_os) == len(present) and len({canon(v) for v in vals_by_os.values()}) == 1:
        return ("shared", next(iter(vals_by_os.values())))
    return ("keyed", vals_by_os)


def invert():
    lib = {}
    for cid in IDS:
        present = [os for os in OSES if cid in DATA[cid_os := os]] if False else [os for os in OSES if cid in DATA[os]]
        entry = {"applicable_os": present}
        for f in SCALAR:
            vals = {os: DATA[os][cid].get(f) for os in present if DATA[os][cid].get(f) is not None}
            if not vals:
                continue
            kind, v = shared_or_keyed(vals, present)
            entry[f] = v if kind == "shared" else {"@os": v}
        norms = {}
        for nm in NORMS:
            vals = {os: (DATA[os][cid].get("norms") or {}).get(nm) for os in present
                    if (DATA[os][cid].get("norms") or {}).get(nm) is not None}
            if not vals:
                continue
            kind, v = shared_or_keyed(vals, present)
            norms[nm] = v if kind == "shared" else {"@os": v}
        if norms:
            entry["norms"] = norms
        lib[cid] = entry
    return lib


def pick(v, os):
    return v["@os"].get(os) if isinstance(v, dict) and "@os" in v else v


def generate(lib):
    out = {os: {} for os in OSES}
    for cid, entry in lib.items():
        for os in entry["applicable_os"]:
            ctrl = {}
            for f in SCALAR:
                if f in entry:
                    val = pick(entry[f], os)
                    if val is not None:
                        ctrl[f] = val
            if "norms" in entry:
                nm = {}
                for k, v in entry["norms"].items():
                    val = pick(v, os)
                    if val is not None:
                        nm[k] = val
                if nm:
                    ctrl["norms"] = nm
            out[os][cid] = ctrl
    return out


def verify(gen):
    total = mismatch = 0
    examples = []
    for os in OSES:
        for cid, orig in DATA[os].items():
            total += 1
            g = gen[os].get(cid, {})
            # compare the fields the library tracks, canonicalised
            for f in SCALAR + ["norms"]:
                a = orig.get("norms") if f == "norms" else orig.get(f)
                b = g.get("norms") if f == "norms" else g.get(f)
                if f == "norms":
                    a = a or {}
                    b = b or {}
                    if {k: canon(v) for k, v in a.items() if v is not None} != {k: canon(v) for k, v in b.items() if v is not None}:
                        mismatch += 1
                        if len(examples) < 6:
                            examples.append((os, cid, "norms"))
                        break
                elif canon(a) != canon(b) and not (a is None and b is None):
                    mismatch += 1
                    if len(examples) < 6:
                        examples.append((os, cid, f))
                    break
    return total, mismatch, examples


lib = invert()
gen = generate(lib)
total, mismatch, examples = verify(gen)

# stats
shared_check = sum(1 for e in lib.values() if "check" in e and not (isinstance(e["check"], dict) and "@os" in e["check"]))
print(f"library: {len(lib)} per-id controls")
print(f"  shared check (defined once): {shared_check}/{len(lib)}")
print(f"\nround-trip: {total - mismatch}/{total} controls identical  ({100*(total-mismatch)//total}%)")
if mismatch:
    print(f"  {mismatch} mismatches, e.g.:")
    for os, cid, f in examples:
        print(f"    {os} {cid} [{f}]")
else:
    print("  ZERO data loss — the per-OS files can become generated, the library the source.")

if "--write" in sys.argv:
    out = ROOT / "docs" / "reference" / "rules-dry.yml"
    out.write_text(yaml.safe_dump(lib, sort_keys=True, allow_unicode=True, width=4096))
    print(f"\nwrote {out} ({out.stat().st_size//1024} KB)")
