#!/usr/bin/env python3
"""Fail if a control has no authored prose, or if prose describes a control that does not exist.

A control lands in `docs/reference/rules.yml` and the scanner runs it on the next generation. Its
PAGE needs what no generator can produce: the bilingual prose in `docs/reference/prose/<id>.json`
(summary, check_note, verify, logs, remediation_note, impact). Nothing offline demanded it, so the
gap was found by `site-deploy` going red on `main`, after the merge, with the whole pipeline built
and the site unreleasable until someone wrote six paragraphs.

`site:verify` already refuses that state, but it REGENERATES `site/src/content/rules/` to do it
(31s, and a pre-push hook must not rewrite the tree it is checking), so it is deliberately out of
`prepush`. The prose half of that check needs neither: the question "does every live control have a
complete bilingual prose file" is answered by two directories on disk, in milliseconds, offline.

So this is that half, extracted. `verify_site_content.py` imports it rather than re-implementing it:
a second copy of a rule is how the two copies start disagreeing.

Four rules:

    a live control (applicable_os is non-empty) has a prose file
    a prose file describes a control that still exists
    a prose file carries the title and the 6 rich fields
    every localized field has an `en` and a `fr`, and the `fr` is not the `en` copied over

The last one exists because the site is bilingual by intent: a French field echoing the English one
is an untranslated page shipped as if it were translated.

Usage: python3 tools/lint_prose_coverage.py [root]     (--selftest proves it bites)
"""

from __future__ import annotations

import json
import pathlib
import sys
import tempfile

import yaml

RICH = ("summary", "check_note", "verify", "logs", "remediation_note", "impact")
REQUIRED = ("title", *RICH)
# `rationale` is optional (most controls carry theirs in rules.yml), but when the prose does declare
# one, it is a page field like any other and gets the same bilingual demand.
LOCALIZED = ("title", "summary", "rationale", *RICH)


def live_controls(rules: pathlib.Path) -> set[str]:
    """The controls an OS actually runs. A control scoped to no OS has no page, by design."""
    src = yaml.safe_load(rules.read_text(encoding="utf-8"))
    return {
        k
        for k, v in src.items()
        if isinstance(v, dict) and "applicable_os" in v and v.get("applicable_os")
    }


def check(root: pathlib.Path) -> list[str]:
    rules = root / "docs" / "reference" / "rules.yml"
    prose_dir = root / "docs" / "reference" / "prose"

    expected = live_controls(rules)
    files = sorted(prose_dir.glob("*.json"))
    have = {p.stem for p in files}

    problems = []
    for rid in sorted(expected - have):
        problems.append(
            f"{rid}: NO PROSE. The scanner runs this control and the site cannot document it. "
            f"Write docs/reference/prose/{rid}.json (EN+FR: {', '.join(REQUIRED)})."
        )
    for rid in sorted(have - expected):
        problems.append(
            f"{rid}: ORPHAN PROSE. No live control carries this id (renamed, deleted, or scoped "
            f"to no OS). Delete docs/reference/prose/{rid}.json or restore the control."
        )

    for p in files:
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            problems.append(f"{p.stem}: unreadable prose file ({e}).")
            continue
        if d.get("id") != p.stem:
            problems.append(f"{p.stem}: the file declares id {d.get('id')!r}, not its own name.")
        for k in REQUIRED:
            if k not in d:
                problems.append(
                    f"{p.stem}: missing {k}. Every page field is authored, not derived."
                )
        for k in LOCALIZED:
            v = d.get(k)
            if v is None:
                continue
            if not isinstance(v, dict) or not v.get("en") or not v.get("fr"):
                problems.append(f"{p.stem}: {k} is not bilingual (it needs a non-empty en and fr).")
            elif v["fr"] == v["en"]:
                problems.append(
                    f"{p.stem}: {k}.fr is the English text copied over, not a French one."
                )
    return problems


# ---- falsification: the linter is only worth its runtime if it can be shown to bite --------------

_MIN_PROSE = {
    "id": "x",
    "title": {"en": "A title", "fr": "Un titre"},
    **{k: {"en": f"the {k}", "fr": f"le {k}"} for k in RICH},
}


def _plant(root: pathlib.Path, controls: dict, prose: dict) -> None:
    (root / "docs" / "reference" / "prose").mkdir(parents=True, exist_ok=True)
    (root / "docs" / "reference" / "rules.yml").write_text(
        yaml.safe_dump(controls, sort_keys=False, allow_unicode=True), encoding="utf-8"
    )
    for rid, d in prose.items():
        (root / "docs" / "reference" / "prose" / f"{rid}.json").write_text(
            json.dumps({**d, "id": rid}, ensure_ascii=False, indent=2), encoding="utf-8"
        )


def _case(name: str, controls: dict, prose: dict, needle: str) -> bool:
    with tempfile.TemporaryDirectory() as tmp:
        tree = pathlib.Path(tmp)
        _plant(tree, controls, prose)
        problems = check(tree)
    if any(needle in p for p in problems):
        print(f"  ok   {name}")
        return True
    print(f"  FAIL {name} was not caught\n{problems}")
    return False


def selftest(root: pathlib.Path) -> int:
    ok = True
    print("lint:prose refuses, on a planted tree:")
    two = {"alpha": {"applicable_os": ["debian12"]}, "beta": {"applicable_os": ["debian12"]}}

    ok &= _case("a control nobody wrote a word about", two, {"alpha": _MIN_PROSE}, "beta: NO PROSE")
    ok &= _case(
        "prose about a control that no longer exists",
        {"alpha": {"applicable_os": ["debian12"]}},
        {"alpha": _MIN_PROSE, "gamma": _MIN_PROSE},
        "gamma: ORPHAN PROSE",
    )
    ok &= _case(
        "a control scoped to no OS still has a page",
        {"alpha": {"applicable_os": ["debian12"]}, "beta": {"applicable_os": []}},
        {"alpha": _MIN_PROSE, "beta": _MIN_PROSE},
        "beta: ORPHAN PROSE",
    )
    ok &= _case(
        "prose with the rich fields but no impact",
        {"alpha": {"applicable_os": ["debian12"]}},
        {"alpha": {k: v for k, v in _MIN_PROSE.items() if k != "impact"}},
        "missing impact",
    )
    ok &= _case(
        "a French field that is the English one copied over",
        {"alpha": {"applicable_os": ["debian12"]}},
        {"alpha": {**_MIN_PROSE, "verify": {"en": "run this", "fr": "run this"}}},
        "verify.fr is the English text",
    )
    ok &= _case(
        "a field that is a bare string instead of the two languages",
        {"alpha": {"applicable_os": ["debian12"]}},
        {"alpha": {**_MIN_PROSE, "logs": "journalctl -u auditd"}},
        "logs is not bilingual",
    )

    print("\nand accepts the tree as it stands:")
    problems = check(root)
    if problems:
        print("  FAIL")
        for p in problems:
            print(f"   {p}")
        return 1
    print("  ok   every live control has complete bilingual prose")
    return 0 if ok else 1


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--selftest"]
    root = pathlib.Path(args[0]) if args else pathlib.Path(__file__).resolve().parent.parent
    if "--selftest" in sys.argv[1:]:
        return selftest(root)

    problems = check(root)
    if problems:
        for p in problems:
            print(p)
        print(f"\n{len(problems)} prose problem(s): the site cannot be built from this tree.")
        return 1
    n = len(live_controls(root / "docs" / "reference" / "rules.yml"))
    print(f"prose: {n} live control(s), each with complete bilingual prose")
    return 0


if __name__ == "__main__":
    sys.exit(main())
