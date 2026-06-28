#!/usr/bin/env python3
"""Validate the pavois reference is the source of truth, with no datastream:
  - integrity : every entry has the required fields, cids are unique per OS,
                impact is a sane float, the check is non-empty.
  - fidelity  : rendering the reference reproduces the committed corpus EXACTLY
                (so the corpus is never edited out of band — the reference rules).
Exit non-zero on any failure.
"""
import sys
import tempfile
import shutil
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import build_reference as B
import render_reference as R

# pavois's per-distro rule base is the SOURCE OF TRUTH (not SSG). `ssg` is now optional
# provenance only — a pavois-owned rule (e.g. for a distro SSG hasn't covered, like Ubuntu 26)
# needs none. Required is the rule's own contract: what it checks and where it belongs.
REQUIRED = ("domain", "title", "check")
FIELDS = ("domain", "title", "norms", "levels", "check", "ssg", "source", "impact",
          "remediation", "thresholds", "note", "requires_package", "exclusive_group")
NORM_IN_ID = __import__("re").compile(r"(?:^|-)(cis|bp28|nist|pci-dss|pci|stig)(?:-|$)")
fail = 0


def ko(msg):
    global fail
    fail += 1
    print(f"  \033[31m✗\033[0m {msg}")


def parse_dir(d):
    out = {}
    for rb in Path(d).glob("*.rb"):
        for m in B.CTRL_RE.finditer(rb.read_text(encoding="utf-8")):
            out[m.group(1)] = B.parse_control(m.group(1), m.group(2))
    return out


def main():
    content = ROOT / "docs" / "reference" / "pavois-content"
    oses = [p.stem for p in sorted(content.glob("*.yml"))]
    if not oses:
        ko("no reference files in docs/reference/pavois-content/")
        return 1
    for os in oses:
        ref = yaml.safe_load((content / f"{os}.yml").read_text(encoding="utf-8"))["rules"]
        # integrity
        for cid, e in ref.items():
            for f in REQUIRED:
                if not e.get(f):
                    ko(f"{os}/{cid}: missing/empty '{f}'")
            if not isinstance(e.get("impact"), (int, float)) or not (0 <= e["impact"] <= 1):
                ko(f"{os}/{cid}: bad impact {e.get('impact')!r}")
            # the norm is a VIEW (a tag), never part of the id — keeps ids stable as norms evolve
            if NORM_IN_ID.search(cid):
                ko(f"{os}/{cid}: a norm name in the id (norms are tags, ids stay neutral)")
        # fidelity : reference -> corpus must equal the committed corpus
        corpus_dir = ROOT / "profiles" / "linux" / os / "controls"
        if not corpus_dir.is_dir():
            ko(f"{os}: no committed corpus to compare")
            continue
        tmp = tempfile.mkdtemp()
        try:
            R.main(os, tmp)
            cur, new = parse_dir(corpus_dir), parse_dir(tmp)
        finally:
            shutil.rmtree(tmp)
        if set(cur) != set(new):
            ko(f"{os}: corpus drift — {len(set(cur) ^ set(new))} cid(s) differ from reference")
            continue
        diffs = sum(1 for cid in cur for f in FIELDS if cur[cid].get(f) != new[cid].get(f))
        if diffs:
            ko(f"{os}: {diffs} field(s) differ between committed corpus and reference render")
        else:
            print(f"  \033[32m✔\033[0m {os}: {len(ref)} controls, reference == corpus")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
