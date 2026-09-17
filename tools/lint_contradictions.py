#!/usr/bin/env python3
"""FAIL when two controls make incompatible demands of the same resource.

Every lint in this repository so far reads ONE control and asks whether it is well formed. None of
them can see the defect where two controls are each correct and cannot both be satisfied, because
the evidence is spread across two entries that no single read brings together.

The case that proves it is in the tree today, and #266 documented it without naming the class:

    file-at-deny-absent      check: /etc/at.deny should_not exist
                             remediation: delete /etc/at.deny
    filegroupowner-at-deny   template: file_owner on /etc/at.deny, gid must be 0

Both are mapped to CIS 2.4.2.1, because the benchmark offers two ways to restrict `at` and the
reference modelled both as mandatory. Apply the pair and the file is deleted, after which the second
control can never pass: a PERMANENT failure on a correctly hardened host, which is the regression
the project's own rules forbid. No syntactic check sees it. Only a check that reasons about the
RESOURCE does.

Four families, each mechanical enough to be worth failing a build over:

  1. absence vs attribute      one control deletes a path, another asserts its owner/group/mode
  2. removed vs required       one control removes a package another needs or installs
  3. one key, two values       two controls set the same sysctl key to different values
  4. one file, two writers     two controls rewrite the same file, so the last apply wins and the
                               other control's setting is silently dropped (this already happened:
                               journald-compress rewrote a shared drop-in and switched off syslog
                               forwarding that a guarded control had deliberately left alone)

A pair is only reported when the two controls apply to at least one system in common: a conflict
between a debian control and an rhel control is not a conflict.

Usage: python3 tools/lint_contradictions.py [--explain]   (--selftest proves it bites)
"""

from __future__ import annotations

import pathlib
import re
import sys
from collections import defaultdict
from typing import Any

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
RULES = ROOT / "docs" / "reference" / "rules.yml"

# Pairs already understood and deliberately kept. Each needs a reason, because an exception with no
# reason is how a guard stops meaning anything. The key is the two ids, sorted.
ACCEPTED: dict[tuple[str, str], str] = {}


CORPUS = ROOT / "profiles" / "linux"
CONTROL_RE = re.compile(r"^control '([^']+)' do\n(.*?)^end$", re.M | re.S)
GUARD_RE = re.compile(r"only_if \{ file\('[^']+'\)\.exist\? \}")


def guarded_controls() -> set[str]:
    """Rendered controls that skip themselves when their file is absent.

    Read from the RENDERED corpus because that is what runs. The reference says what a control
    asserts; the renderer decides whether it asserts it unconditionally. Returns an empty set when
    the corpus is not rendered, which the caller treats as "cannot tell" rather than "none".
    """
    out: set[str] = set()
    for rb in sorted(CORPUS.glob("*/controls/*.rb")):
        for m in CONTROL_RE.finditer(rb.read_text(encoding="utf-8")):
            if GUARD_RE.search(m.group(2)):
                out.add(m.group(1))
    return out


def remediations(c: dict[str, Any]) -> list[dict[str, Any]]:
    """A control's remediation entries, however they are written (one, a list, or @os-keyed)."""
    r = c.get("remediation")
    out: list[dict[str, Any]] = []
    if isinstance(r, dict):
        # An @os-keyed remediation holds per-system variants under that key.
        if "@os" in r and isinstance(r["@os"], dict):
            for v in r["@os"].values():
                if isinstance(v, dict):
                    out.append(v)
            rest = {k: v for k, v in r.items() if k != "@os"}
            if rest.get("resource"):
                out.append(rest)
        else:
            out.append(r)
    elif isinstance(r, list):
        out.extend(x for x in r if isinstance(x, dict))
    return out


def check_text(c: dict[str, Any]) -> str:
    chk = c.get("check")
    if isinstance(chk, list):
        return "\n".join(str(x) for x in chk)
    return str(chk or "")


def systems(c: dict[str, Any]) -> set[str]:
    return set(c.get("applicable_os") or [])


PATH_IN_CHECK = re.compile(r"file\('([^']+)'\)")


def as_set(v: Any) -> set[str]:
    """A field that is sometimes a string, sometimes a list, sometimes absent.

    rules.yml is hand-written and both shapes occur for `action`, `name` and `path`. Assuming one
    of them raised TypeError: unhashable type on the first real run, which is the cheap version of
    the same lesson this whole file is about: read what is there, not what you expected.
    """
    if v is None:
        return set()
    if isinstance(v, (list, tuple, set)):
        return {str(x) for x in v}
    return {str(v)}


def deleted_paths(c: dict[str, Any]) -> set[str]:
    """Paths this control removes, or asserts the absence of."""
    out = set()
    for r in remediations(c):
        deletes = bool(as_set(r.get("action")) & {"delete", "remove"})
        if as_set(r.get("resource")) & {"file", "directory"} and deletes:
            out |= as_set(r.get("path"))
    text = check_text(c)
    if "should_not exist" in text:
        out.update(PATH_IN_CHECK.findall(text))
    return out


def attributed_paths(c: dict[str, Any]) -> set[str]:
    """Paths whose owner, group or mode this control asserts: they have to exist to have one."""
    out = set()
    t = c.get("template")
    if isinstance(t, dict) and t.get("name") in {"file_owner", "file_perms"} and t.get("path"):
        out.add(str(t["path"]))
    for r in remediations(c):
        has_attr = any(k in r for k in ("owner", "group", "mode"))
        kept = not (as_set(r.get("action")) & {"delete", "remove"})
        if as_set(r.get("resource")) & {"file", "directory"} and has_attr and kept:
            out |= as_set(r.get("path"))
    return out


def written_paths(c: dict[str, Any]) -> set[str]:
    """Paths whose CONTENT this control writes: two writers of one file is last-apply-wins."""
    out = set()
    for r in remediations(c):
        if "file" in as_set(r.get("resource")) and "content" in r:
            out |= as_set(r.get("path"))
        if "conf_line" in as_set(r.get("resource")):
            out |= as_set(r.get("path"))
    return out


def package_actions(c: dict[str, Any]) -> tuple[set[str], set[str]]:
    """(packages this control removes, packages it installs or depends on)."""
    removed, needed = set(), set()
    for r in remediations(c):
        if "package" not in as_set(r.get("resource")):
            continue
        names = as_set(r.get("name")) or as_set(r.get("package"))
        if not names:
            continue
        if as_set(r.get("action")) & {"remove", "purge"}:
            removed |= names
        else:
            needed |= names
    needed |= as_set(c.get("requires_package"))
    return removed, needed


def sysctl_settings(c: dict[str, Any]) -> dict[str, str]:
    out = {}
    for r in remediations(c):
        if "sysctl" in as_set(r.get("resource")) and r.get("key") is not None:
            out[str(r["key"])] = str(r.get("value"))
    t = c.get("template")
    if isinstance(t, dict) and t.get("name") == "sysctl" and t.get("key") is not None:
        out.setdefault(str(t["key"]), str(t.get("value")))
    return out


def find(rules: dict[str, Any]) -> list[str]:
    ctrls = {k: v for k, v in rules.items() if isinstance(v, dict) and "applicable_os" in v}
    problems: list[str] = []

    def accepted(a: str, b: str) -> bool:
        return tuple(sorted((a, b))) in ACCEPTED

    def overlap(a: str, b: str) -> set[str]:
        return systems(ctrls[a]) & systems(ctrls[b])

    # 1. One control removes a path, another asserts an attribute of it.
    del_by_path: dict[str, list[str]] = defaultdict(list)
    attr_by_path: dict[str, list[str]] = defaultdict(list)
    for cid, c in ctrls.items():
        for p in deleted_paths(c):
            del_by_path[p].append(cid)
        for p in attributed_paths(c):
            attr_by_path[p].append(cid)
    guarded = guarded_controls()
    for path in sorted(set(del_by_path) & set(attr_by_path)):
        for a in sorted(del_by_path[path]):
            for b in sorted(attr_by_path[path]):
                if a == b or accepted(a, b) or not (common := overlap(a, b)):
                    continue
                # The RENDERED control decides, not the reference. `file_owner` renders with
                # `only_if { file(p).exist? }`, so deleting the file SKIPS the attribute control
                # instead of failing it, and the pair is merely redundant. The first version of
                # this rule did not look, reported these four pairs as permanent failures, and was
                # wrong on every one of them: 642 such controls are rendered, 642 carry the guard.
                # A linter that cries wolf four times is one people learn to skip.
                if b in guarded:
                    continue
                problems.append(
                    f"{path}: {a} removes it, {b} asserts its owner/group/mode UNGUARDED\n"
                    f"  both apply to {', '.join(sorted(common))}\n"
                    f"  {b} renders with no existence guard, so applying the pair deletes\n"
                    f"  the file and {b} then fails forever on a correctly hardened host"
                )

    # 2. One control removes a package another needs.
    removes: dict[str, list[str]] = defaultdict(list)
    needs: dict[str, list[str]] = defaultdict(list)
    for cid, c in ctrls.items():
        rem, need = package_actions(c)
        for p in rem:
            removes[p].append(cid)
        for p in need:
            needs[p].append(cid)
    for pkg in sorted(set(removes) & set(needs)):
        for a in sorted(removes[pkg]):
            for b in sorted(needs[pkg]):
                if a == b or accepted(a, b) or not (common := overlap(a, b)):
                    continue
                problems.append(
                    f"package {pkg}: {a} removes it, {b} needs it\n"
                    f"  both apply to {', '.join(sorted(common))}\n"
                    f"  the order of the apply decides which holds, and the plan does not fix it"
                )

    # 3. Two controls set the same sysctl key to different values.
    by_key: dict[str, dict[str, str]] = defaultdict(dict)
    for cid, c in ctrls.items():
        for k, v in sysctl_settings(c).items():
            by_key[k][cid] = v
    for key, setters in sorted(by_key.items()):
        ids = sorted(setters)
        for i, a in enumerate(ids):
            for b in ids[i + 1 :]:
                if setters[a] == setters[b] or accepted(a, b) or not (common := overlap(a, b)):
                    continue
                problems.append(
                    f"sysctl {key}: {a} sets {setters[a]}, {b} sets {setters[b]}\n"
                    f"  both apply to {', '.join(sorted(common))}\n"
                    f"  one of them reports a deviation on a host the other just configured"
                )

    # 4. Two controls write the same file.
    writers: dict[str, list[str]] = defaultdict(list)
    for cid, c in ctrls.items():
        for p in written_paths(c):
            writers[p].append(cid)
    for path, ids in sorted(writers.items()):
        ids = sorted(ids)
        for i, a in enumerate(ids):
            for b in ids[i + 1 :]:
                if accepted(a, b) or not (common := overlap(a, b)):
                    continue
                problems.append(
                    f"{path}: written by both {a} and {b}\n"
                    f"  both apply to {', '.join(sorted(common))}\n"
                    f"  the last apply wins and silently drops the other's setting; this has"
                    f" happened\n  (a journald drop-in rewrite switched off syslog forwarding"
                    f" another control had left alone)"
                )

    return problems


def load(path: pathlib.Path) -> dict[str, Any]:
    d = yaml.safe_load(path.read_text(encoding="utf-8"))
    return d.get("controls", d)


def selftest() -> int:
    """Plant a contradiction that is not in the tree and demand it is caught."""
    print("the contradiction linter rejects:")
    rules = load(RULES)
    base = {"applicable_os": ["debian12"], "severity": "medium"}
    rules["zz-test-removes-tool"] = {
        **base,
        "title": "test",
        "remediation": {"resource": "package", "action": "remove", "name": "zz-fictional-pkg"},
    }
    rules["zz-test-needs-tool"] = {
        **base,
        "title": "test",
        "requires_package": "zz-fictional-pkg",
        "remediation": {"resource": "exec", "command": "true"},
    }
    problems = find(rules)
    if any("zz-fictional-pkg" in p for p in problems):
        print("  ok   a package one control removes and another needs")
    else:
        print("  FAIL the planted package conflict was not caught")
        return 1

    rules["zz-test-deletes"] = {
        **base,
        "title": "test",
        "remediation": {"resource": "file", "action": "delete", "path": "/etc/zz-fictional"},
    }
    rules["zz-test-owns"] = {
        **base,
        "title": "test",
        "template": {
            "name": "file_owner",
            "path": "/etc/zz-fictional",
            "attr": "gid",
            "value": "0",
        },
    }
    problems = find(rules)
    if any("/etc/zz-fictional" in p for p in problems):
        print("  ok   a path one control deletes and another owns")
        return 0
    print("  FAIL the planted path conflict was not caught")
    return 1


def main() -> int:
    if not RULES.exists():
        print(f"missing {RULES.relative_to(ROOT)}")
        return 1
    if "--selftest" in sys.argv[1:]:
        return selftest()

    rules = load(RULES)
    ctrls = {k: v for k, v in rules.items() if isinstance(v, dict) and "applicable_os" in v}
    # An empty read is not a clean tree. If the file moves, the schema changes or a key is renamed,
    # every extractor returns nothing and this would announce success having compared no pair at
    # all. Same shape as lint:shell-first-word finding an unrendered corpus.
    if len(ctrls) < 100:
        print(f"lint:contradictions: only {len(ctrls)} control(s) parsed from rules.yml")
        print("That is not a clean tree, it is a reader that stopped reading. Check the schema.")
        return 1
    if not CORPUS.is_dir():
        print("lint:contradictions: no rendered corpus; run `mise run render` first")
        print("The rendered controls decide whether a pair is a real failure or merely redundant.")
        return 1

    problems = find(rules)
    if problems:
        print(f"lint:contradictions: {len(problems)} pair(s) cannot both be satisfied\n")
        for p in problems:
            print(f"  {p}\n")
        print("Each pair needs a decision, not a tweak: which control states the requirement, and")
        print("what the other becomes (scoped to a system, made conditional, or an accepted pair")
        print("with its reason recorded in ACCEPTED).")
        return 1
    print(f"lint:contradictions: {len(ctrls)} control(s) compared, no pair makes incompatible")
    print("  demands of one file, package, sysctl key or configuration file")
    return 0


if __name__ == "__main__":
    sys.exit(main())
