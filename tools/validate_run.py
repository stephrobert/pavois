#!/usr/bin/env python3
"""Is this scan TRUSTWORTHY? A different question from "is this machine compliant?".

    tools/validate_run.py <scan.json> [--json] [--strict]

A scan answers "is the machine compliant". This answers "did the scan actually measure anything",
which nothing checked until three families of broken controls were found in one day, each by a
different accident:

  * 19 controls started with a shell keyword. `sudo for ...` is not a command, stdout was empty,
    and the matcher reported a deviation on a host that was configured correctly.
  * 19 more started with `v=$(...)`. Same cause, a shape the first lint did not know.
  * 58 more, double-quoted, did the same but printed a confident "ko" instead of nothing, because
    the unset variable took the failure branch. The silent-control detector saw nothing wrong.
    Among them the 55 kconfig controls, which is why a hardened kernel reported 2/57.

The lesson is in the third one: a silent control is detectable, a control that answers WRONGLY is
not, at least not one at a time. What gives it away is the SHAPE OF THE FAILURES. Real deviations
are scattered; a broken harness fails whole families at once and repeats itself word for word.

Checks, roughly in order of how certain they are:

  R1 empty-output      a failing test whose command returned nothing at all      ERROR
  R2 shell-error       output carrying "command not found", "Permission denied"  ERROR
  R3 identical-message N failures sharing the exact same message                 warning
  R4 family-wipeout    a domain wiped out while the rest of the scan is healthy  warning
  R5 no-evidence       a failure with neither an expectation nor a result        warning

KNOWN LIMIT, and it is why R3 and R4 are warnings rather than errors: they cannot tell a broken
mechanism from an ABSENT one. On a stock machine this run reported 11 of them, and every single one
was legitimate: the 29 auditd controls all fail because no audit rule is loaded, and 109 controls
repeat the same message for the same reason, once each. Nothing was broken, nothing was configured.

So R3 and R4 are worth reading AFTER hardening, where the rest of the scan passes and a family
still failing as a block really is suspicious. R1 and R2 hold in every case, which is why they are
the only ones that fail a campaign.

Exit 1 on errors. --strict also fails on warnings, which you want on a hardened machine and
definitely not on a stock one.
"""

from __future__ import annotations

import collections
import json
import re
import sys
from pathlib import Path

GOT_RE = re.compile(r"got:\s*\"((?:[^\"\\]|\\.)*)\"", re.S)
EXPECTED_RE = re.compile(r"expected:\s*\"((?:[^\"\\]|\\.)*)\"", re.S)

# Strings that mean the probe itself failed, not that the system deviates.
SHELL_ERRORS = (
    "command not found",
    "No such file or directory",
    "Permission denied",
    "usage: sudo",
    "sudo: a terminal is required",
    "a password is required",
    "unbound variable",
    "syntax error",
)

# A family that fails as a block is one cause. Below these thresholds it is just a bad day.
FAMILY_MIN = 5
FAMILY_RATIO = 0.9
IDENTICAL_MIN = 8


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def iter_results(report: dict):
    for profile in report.get("profiles", []):
        for control in profile.get("controls", []):
            for result in control.get("results", []):
                yield control, result


def family_of(control: dict) -> str:
    """Group by the control's domain tag when it has one, else by the id prefix. Controls that
    share a mechanism share a family, which is what makes a block failure meaningful."""
    tags = control.get("tags") or {}
    domain = tags.get("domain")
    if domain:
        return str(domain)
    cid = control.get("id", "?")
    return cid.split("-", 1)[0] if "-" in cid else cid


def analyse(report: dict) -> dict:
    errors: list[tuple[str, str]] = []
    warnings: list[tuple[str, str]] = []

    per_family_total = collections.Counter()
    per_family_failed = collections.Counter()
    message_counts = collections.Counter()
    message_examples: dict[str, list[str]] = collections.defaultdict(list)
    total = failed = 0

    for control, result in iter_results(report):
        cid = control.get("id", "?")
        fam = family_of(control)
        per_family_total[fam] += 1
        total += 1
        status = result.get("status")
        if status != "failed":
            continue
        failed += 1
        per_family_failed[fam] += 1
        msg = result.get("message") or ""

        got = GOT_RE.search(msg)
        exp = EXPECTED_RE.search(msg)

        # R1: nothing came back.
        if got and exp and got.group(1).strip() == "" and exp.group(1).strip() != "":
            errors.append(
                ("empty-output", f"{cid}: expected {exp.group(1)!r}, the command returned nothing")
            )
            continue

        # R2: the probe itself broke.
        low = msg.lower()
        for marker in SHELL_ERRORS:
            if marker.lower() in low:
                errors.append(("shell-error", f"{cid}: the command reported {marker!r}"))
                break
        else:
            # R5: a failure with nothing to show.
            if not got and not exp and len(msg.strip()) < 2:
                warnings.append(("no-evidence", f"{cid}: failed with no expectation and no result"))

        # R3 material: normalise the message so identical causes collapse together.
        norm = re.sub(r"\s+", " ", msg.strip())[:200]
        if norm:
            message_counts[norm] += 1
            if len(message_examples[norm]) < 4:
                message_examples[norm].append(cid)

    # R3: many failures sharing one message.
    for msg, n in message_counts.items():
        if n >= IDENTICAL_MIN:
            examples = ", ".join(message_examples[msg])
            warnings.append(
                (
                    "identical-message",
                    f"{n} controls fail with the SAME message ({examples}, ...): "
                    f"suspect one cause, not {n}",
                )
            )

    # R4: a family wiped out while the scan as a whole is healthy.
    overall_fail_ratio = (failed / total) if total else 0
    for fam, ftotal in per_family_total.items():
        ffailed = per_family_failed.get(fam, 0)
        if ftotal >= FAMILY_MIN and ffailed / ftotal >= FAMILY_RATIO and overall_fail_ratio < 0.5:
            warnings.append(
                (
                    "family-wipeout",
                    f"{fam}: {ffailed}/{ftotal} fail while the scan overall fails "
                    f"{overall_fail_ratio:.0%}: suspect the mechanism, not the controls",
                )
            )

    return {
        "total": total,
        "failed": failed,
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv
    strict = "--strict" in sys.argv
    if not args:
        print("usage: validate_run.py <scan.json> [--json] [--strict]", file=sys.stderr)
        return 2

    try:
        report = load(Path(args[0]))
    except Exception as exc:  # noqa: BLE001
        print(f"cannot read {args[0]}: {exc}", file=sys.stderr)
        return 2

    res = analyse(report)

    if as_json:
        print(json.dumps(res, indent=2))
        return 1 if res["errors"] or (strict and res["warnings"]) else 0

    print(f"run-validation: {res['total']} test(s), {res['failed']} failing\n")

    if res["errors"]:
        print(f"ERRORS ({len(res['errors'])}): the scan did not measure what it reported")
        for kind, detail in res["errors"][:30]:
            print(f"  [{kind}] {detail}")
        if len(res["errors"]) > 30:
            print(f"  ... and {len(res['errors']) - 30} more")
        print()

    if res["warnings"]:
        print(f"WARNINGS ({len(res['warnings'])}): shapes that usually mean one broken mechanism")
        for kind, detail in res["warnings"][:20]:
            print(f"  [{kind}] {detail}")
        if len(res["warnings"]) > 20:
            print(f"  ... and {len(res['warnings']) - 20} more")
        print()

    if not res["errors"] and not res["warnings"]:
        print("run-validation: no sign that any verdict was invented")
        print("run-validation: failures are scattered and each one produced evidence")
        return 0

    print("A failure that produced no evidence, or a whole family failing at once, is far more")
    print("often a broken probe than a broken machine. Read those before reading the report.")
    return 1 if res["errors"] or strict else 0


if __name__ == "__main__":
    sys.exit(main())
