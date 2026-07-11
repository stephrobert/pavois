#!/usr/bin/env python3
"""Reconcile a target OS into controls it is missing from applicable_os.

The per-OS curation of docs/reference/rules.yml dropped norm-mapped controls
unevenly across the 8 OSes (a control present on debian12/13 but absent from
ubuntu2404 is almost always a curation gap, not a real inapplicability). This
tool extends a target OS onto controls by MIRRORING a reference OS: it adds the
target to `applicable_os` and, for every `@os`-keyed subtree (check / remediation
/ norms / levels ...), copies the reference OS's value under the target key so the
generator (tools/gen.py, which has no @os fallback) renders correctly.

It NEVER touches the reference OS's own values, so a golden baseline stays
byte-identical after regeneration. Every extension MUST still be validated by a
real `pavois scan` on the target VM (rules/CLAUDE.md non-negotiable): this tool
only removes the mechanical toil, it does not prove applicability.

Usage:
  reconcile_os.py --target ubuntu2404 --ref debian13 \
      --controls a,b,c            # explicit list
  reconcile_os.py --target ubuntu2404 --ref debian13 \
      --auto-family               # every control on BOTH family anchors but not target
  reconcile_os.py ... --exclude x,y   --dry-run
"""
import argparse
import copy
import sys
from ruamel.yaml import YAML

RULES = "docs/reference/rules.yml"
# family anchors used by --auto-family: a control on both anchors of the target's
# family but not on the target is a strong curation-gap signal.
FAMILY = {
    "debian12": ("debian12", "debian13"), "debian13": ("debian12", "debian13"),
    "ubuntu2204": ("debian12", "debian13"), "ubuntu2404": ("debian12", "debian13"),
    "rhel8": ("rhel8", "rhel9"), "rhel9": ("rhel8", "rhel9"),
    "rhel10": ("rhel8", "rhel9"), "fedora": ("rhel8", "rhel9"),
}


def mirror_os_keys(node, ref, target):
    """Recursively copy ref -> target inside every @os map. Returns #mirrored."""
    n = 0
    if isinstance(node, dict):
        for k, v in list(node.items()):
            if k == "@os" and isinstance(v, dict):
                if ref in v and target not in v:
                    v[target] = copy.deepcopy(v[ref])
                    n += 1
            else:
                n += mirror_os_keys(v, ref, target)
    elif isinstance(node, list):
        for item in node:
            n += mirror_os_keys(item, ref, target)
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", required=True)
    ap.add_argument("--ref", required=True)
    ap.add_argument("--controls", default="")
    ap.add_argument("--auto-family", action="store_true")
    ap.add_argument("--mirror", action="store_true",
                    help="onboard a sibling: add target to EVERY control the ref applies to")
    ap.add_argument("--exclude", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    # keep explicit `null` in list items (default ruamel renders None as empty),
    # so the only diff is the controls we actually touch.
    yaml.representer.add_representer(
        type(None),
        lambda r, _: r.represent_scalar("tag:yaml.org,2002:null", "null"),
    )
    with open(RULES) as f:
        d = yaml.load(f)

    exclude = {c for c in a.exclude.split(",") if c}
    if a.mirror:
        # onboard a sibling OS: extend the target onto EVERY control the ref already applies to,
        # mirroring the ref's @os values. Used to seed a new release from its closest sibling
        # (e.g. ubuntu2604 from ubuntu2404) — 26.04 hardens like 24.04.
        want = [
            c for c, v in d.items()
            if isinstance(v, dict) and isinstance(v.get("applicable_os"), list)
            and a.ref in v["applicable_os"] and a.target not in v["applicable_os"]
        ]
    elif a.auto_family:
        anchors = FAMILY[a.target]
        want = [
            c for c, v in d.items()
            if isinstance(v, dict) and isinstance(v.get("applicable_os"), list)
            and all(x in v["applicable_os"] for x in anchors)
            and a.target not in v["applicable_os"]
        ]
    else:
        want = [c for c in a.controls.split(",") if c]
    want = [c for c in want if c not in exclude]

    added, mirrored, skipped = [], [], []
    for c in want:
        v = d.get(c)
        if not isinstance(v, dict) or not isinstance(v.get("applicable_os"), list):
            skipped.append((c, "no applicable_os")); continue
        if a.target in v["applicable_os"]:
            skipped.append((c, "already present")); continue
        if a.ref not in v["applicable_os"]:
            skipped.append((c, f"ref {a.ref} not applicable")); continue
        # insert target right after ref to keep the list readable
        lst = v["applicable_os"]
        lst.insert(lst.index(a.ref) + 1, a.target)
        m = mirror_os_keys(v, a.ref, a.target)
        added.append(c)
        if m:
            mirrored.append((c, m))

    print(f"target={a.target} ref={a.ref}  candidates={len(want)}")
    print(f"ADDED {len(added)}: {', '.join(added)}")
    if mirrored:
        print("  @os mirrored: " + ", ".join(f"{c}(+{m})" for c, m in mirrored))
    if skipped:
        print("skipped: " + ", ".join(f"{c}[{r}]" for c, r in skipped))

    if a.dry_run:
        print("\n(dry-run, not written)")
        return
    if added:
        with open(RULES, "w") as f:
            yaml.dump(d, f)
        print(f"\nwrote {RULES}")


if __name__ == "__main__":
    main()
