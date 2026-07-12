#!/usr/bin/env python3
"""The DRY pipeline. docs/reference/rules.yml is THE source (one per-id control: shared fields once
+ values keyed @os only where they differ). The 8 docs/reference/pavois-content/<os>.yml are
DERIVED build artifacts.

  tools/gen.py invert   # 8 OS files  -> rules.yml          (one-time, to seed the source)
  tools/gen.py render   # rules.yml   -> 8 OS files          (build step after editing rules.yml)
  tools/gen.py verify   # render(rules.yml) == committed 8 OS files, semantically (CI guard)

Editing model: change rules.yml ONCE, run `render`, then the existing renderers (render.sh,
generate_rule_pages.py, `pavois oscal`) produce the corpus, site fiches and OSCAL.
"""

import json
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import templates  # noqa: E402  (check templates: a control's `template` expands to its check)

ROOT = Path(__file__).resolve().parent.parent
REF = ROOT / "docs" / "reference" / "pavois-content"
SRC = ROOT / "docs" / "reference" / "rules.yml"
OSES = sorted(p.stem for p in REF.glob("*.yml"))
# every per-control field except `norms` (handled separately).
# MUST be exhaustive or render drops data.
SCALAR = [
    "check",
    "domain",
    "severity",
    "impact",
    "title",
    "remediation",
    "ssg",
    "levels",
    "socle",
    "evidence_type",
    "reboot_survivable",
    "requires_companion_control",
    "requires_package",
    "posture",
    "remediation_class",  # auto | dangerous | install-time | kernel-build | manual
    "replaces",
    "merge_group",
    "thresholds",
    "note",
    "exclusive_group",
    "danger",
    "waiver",  # accepted risk: justification for a control we deliberately do NOT enforce
]
NORMS = ["bp28", "nist", "pci-dss", "cis", "stig"]


def load_os():
    return {os: yaml.safe_load((REF / f"{os}.yml").read_text())["rules"] for os in OSES}


def canon(v):
    if isinstance(v, list):
        return json.dumps(sorted(json.dumps(x, sort_keys=True) for x in v))
    return json.dumps(v, sort_keys=True)


def invert(data):
    ids = sorted({k for os in OSES for k in data[os]})
    lib = {}
    for cid in ids:
        present = [os for os in OSES if cid in data[os]]
        entry = {"applicable_os": present}
        for f in SCALAR:
            vals = {os: data[os][cid].get(f) for os in present if data[os][cid].get(f) is not None}
            if not vals:
                continue
            if len(vals) == len(present) and len({canon(v) for v in vals.values()}) == 1:
                entry[f] = next(iter(vals.values()))
            else:
                entry[f] = {"@os": vals}
        norms = {}
        for nm in NORMS:
            vals = {
                os: (data[os][cid].get("norms") or {}).get(nm)
                for os in present
                if (data[os][cid].get("norms") or {}).get(nm) is not None
            }
            if not vals:
                continue
            if len(vals) == len(present) and len({canon(v) for v in vals.values()}) == 1:
                norms[nm] = next(iter(vals.values()))
            else:
                norms[nm] = {"@os": vals}
        if norms:
            entry["norms"] = norms
        lib[cid] = entry
    return lib


OS_PROFILES = {}  # {os: primitives}, loaded lazily from docs/reference/os/<os>.yml


def profile(os):
    """The OS primitive profile: the ~40 facts that make a control distro-specific (package
    names, grub dir, the group that owns /var/log...). A control references them as @{pkg.httpd}
    instead of carrying nine copies of the same value, so a wrong fact is fixed in ONE cell
    instead of hiding in one @os block among a thousand. That is how the phantom RHEL package
    names sat unnoticed in the debian columns."""
    if os not in OS_PROFILES:
        p = ROOT / "docs" / "reference" / "os" / f"{os}.yml"
        OS_PROFILES[os] = yaml.safe_load(p.read_text()) if p.exists() else {}
    return OS_PROFILES[os]


# Sigil: @{...}. NOT ${...} (shell remediations use it: `for u in ...; do ... ${u}.service`)
# and NOT %{...} (harden.go uses %{path} in a file `verify:` command).
VAR = re.compile(r"@\{([a-z_][\w.]*)\}")


def subst(v, os, cid):
    """Resolve @{primitive} against the OS profile. An unknown primitive is a HARD ERROR: it must
    never render as an empty string, because package('') is installed nowhere and would pass
    forever — a vacuous control, the very thing we are hunting."""
    if isinstance(v, str):

        def one(m):
            node = profile(os)
            for part in m.group(1).split("."):
                if not isinstance(node, dict) or part not in node:
                    raise SystemExit(f"{cid} [{os}]: unknown primitive @{{{m.group(1)}}}")
                node = node[part]
            if node is None or node == "":
                raise SystemExit(f"{cid} [{os}]: primitive @{{{m.group(1)}}} is empty")
            return str(node)

        return VAR.sub(one, v)
    if isinstance(v, list):
        return [subst(x, os, cid) for x in v]
    if isinstance(v, dict):
        return {k: subst(x, os, cid) for k, x in v.items()}
    return v


def pick(v, os):
    """Resolve a field for one OS: the @os override, else `default`, else the shared value.

    Without the `default` fallback, a field written `@os: {debian12: ...}` silently resolved to
    None on the eight other OSes and vanished from the render. That single missing line is what
    produced 123 rhel10 controls with NO remediation at all against 3 on debian12: not 123
    oversights, one generator semantics defect, multiplied. `default` makes the portable value
    explicit and the hole a deliberate one.
    """
    if isinstance(v, dict) and "@os" in v:
        return v["@os"].get(os, v.get("default"))
    return v


def render(lib):
    # OS set comes from the SOURCE (rules.yml), never from the (derived) output dir —
    # so render works on a fresh clone where pavois-content/ does not exist yet.
    oses = sorted({os for entry in lib.values() for os in entry["applicable_os"]})
    out = {os: {} for os in oses}
    for cid, entry in lib.items():
        for os in entry["applicable_os"]:
            ctrl = {}
            for f in SCALAR:
                if f in entry:
                    val = pick(entry[f], os)
                    if val is not None:
                        ctrl[f] = subst(val, os, cid)
            if "norms" in entry:
                nm = {k: pick(v, os) for k, v in entry["norms"].items() if pick(v, os) is not None}
                if nm:
                    ctrl["norms"] = nm
            if "template" in entry:  # check defined once as a template -> expand to verbatim check
                t = pick(entry["template"], os)
                if t is not None:
                    ctrl["check"] = templates.expand(subst(t, os, cid))
            out[os][cid] = ctrl
    return out


def semeq(a, b):
    """Semantic equality of two control dicts (lists order-insensitive)."""
    keys = set(a) | set(b)
    for k in keys:
        if k == "norms":
            an = {x: canon(y) for x, y in (a.get("norms") or {}).items() if y is not None}
            bn = {x: canon(y) for x, y in (b.get("norms") or {}).items() if y is not None}
            if an != bn:
                return False
        elif canon(a.get(k)) != canon(b.get(k)):
            return False
    return True


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "invert":
        lib = invert(load_os())
        SRC.write_text(yaml.safe_dump(lib, sort_keys=True, allow_unicode=True, width=4096))
        shared = sum(
            1
            for e in lib.values()
            if "check" in e and not (isinstance(e["check"], dict) and "@os" in e["check"])
        )
        print(f"invert: {len(lib)} controls -> {SRC.relative_to(ROOT)}  (shared check: {shared})")
        return 0
    lib = yaml.safe_load(SRC.read_text())
    gen = render(lib)
    if mode == "render":
        REF.mkdir(parents=True, exist_ok=True)
        for os in gen:
            (REF / f"{os}.yml").write_text(
                yaml.safe_dump({"rules": gen[os]}, sort_keys=True, allow_unicode=True, width=80)
            )
        print(f"render: {SRC.relative_to(ROOT)} -> {len(gen)} OS files")
        return 0
    # verify
    data = load_os()
    total = bad = 0
    for os in OSES:
        for cid, orig in data[os].items():
            total += 1
            if not semeq(orig, gen[os].get(cid, {})):
                bad += 1
                if bad <= 5:
                    print(f"  MISMATCH {os} {cid}")
    print(f"verify: {total - bad}/{total} controls in sync ({100 * (total - bad) // total}%)")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
