#!/usr/bin/env python3
"""Keep the redistribution claim true: norm mappings must hold REFERENCES, never prose.

/attribution tells the reader, in both languages:

    Pavois maps only the reference numbers of each standard (facts); it does not reproduce
    the prose of the CIS, PCI-DSS or other benchmark documents.

That is the sentence the whole licensing position rests on. A section number is a fact and
carries no copyright; the sentence explaining what the section requires is the benchmark's text,
and CIS in particular does not grant redistribution of it. Today the claim holds: 5348 mappings
across five frameworks, every one of them an identifier.

Nothing enforced it. One contributor pasting a requirement's wording into a `cis:` value, meaning
well, would silently turn a defensible position into an infringing one, and the page would go on
promising otherwise. So this checks the shape of every mapping value:

  - identifiers only: digits, dots, dashes, and the short alphanumeric forms real catalogues use
    (AC-17(a), 3.1.1, 5.4.2.1, V-230234, R33, 8.2.1)
  - nothing that reads as a sentence: spaces beyond a joining word, prose punctuation, or length

And one rule about `ssg:`, which is provenance rather than a norm mapping but fails the same way.
An `ssg` value equal to the control's own id is not a mapping: it is "this control has no SSG rule"
written so that every tool believes it has one. `tools/coverage_gap.py` counted 11 such controls as
covered, and a reader of the fiche saw an upstream reference that does not exist. A pavois-native
control simply omits the field, which is what the growth-* family already does.

  mise run lint:norm-refs
"""

from __future__ import annotations

import re
import sys

import yaml

RULES = "docs/reference/rules.yml"

# What a reference looks like across the five catalogues pavois maps:
#   CIS      5.4.2.1, 8.2.1
#   BP-28    R33, R68
#   NIST     AC-17(a), CM-6(a), 3.1.1, IA-2(5)
#   PCI DSS  2.2.6, 8.3.6
#   STIG     V-230234, RHEL-08-010030
#
# NIST writes its enhancements both ways in the wild, and the corpus carries both: "AC-17(a)" and
# "AC-6 (1)", "AU-12 b". A single interior space is therefore allowed. The point is to catch PROSE,
# not to impose a house style on a catalogue that does not have one: nothing under 40 characters
# with at most one space is a sentence from a benchmark.
# The space in the repeated group is MANDATORY, and that single character is the whole fix. With
# `(?: ?[...]+)*` the group could match without consuming a space, so it overlapped the `[...]*`
# before it and the engine had exponentially many ways to split the same text. Measured on
# "0" + "(" * 26: 3.6 seconds before, unmeasurable after, for the same accepted language.
REFERENCE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9./()\[\]_-]*(?: [A-Za-z0-9./()\[\]_-]+)*$")

# A value that is not a reference is almost always a fragment of the standard's own wording, which
# is the thing that must not be stored. Report it with enough context to fix it.
MAX_LEN = 40


def offenders(path: str) -> list[str]:
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    rules = doc["rules"] if isinstance(doc, dict) and "rules" in doc else doc
    items = rules.items() if isinstance(rules, dict) else [(r.get("id"), r) for r in rules]

    bad: list[str] = []
    seen = 0
    for rid, rule in items:
        for ssg in flatten(rule.get("ssg")):
            if ssg == rid:
                bad.append(
                    f"{rid}: ssg: points at the control itself, which is not a mapping: "
                    f"omit the field on a pavois-native control"
                )
        for norm, value in (rule.get("norms") or {}).items():
            for ref in flatten(value):
                seen += 1
                spaces = ref.count(" ")
                if len(ref) > MAX_LEN or spaces > 1 or not REFERENCE.match(ref):
                    why = (
                        "too long"
                        if len(ref) > MAX_LEN
                        else "reads as prose"
                        if spaces > 1
                        else "not an identifier"
                    )
                    bad.append(f"{rid}: {norm}: {why}: {ref[:70]!r}")
    print(f"lint:norm-refs: {seen} mapping(s) checked")
    return bad


def flatten(value) -> list[str]:
    """Mappings are keyed by OS and may be a scalar or a list at any depth."""
    out: list[str] = []
    if isinstance(value, dict):
        for v in value.values():
            out += flatten(v)
    elif isinstance(value, list):
        for v in value:
            out += flatten(v)
    elif value is not None:
        out.append(str(value))
    return out


def main() -> int:
    bad = offenders(RULES)
    if bad:
        print(
            f"lint:norm-refs: {len(bad)} mapping(s) hold something other than a reference",
            file=sys.stderr,
        )
        for line in bad[:30]:
            print("  " + line, file=sys.stderr)
        if len(bad) > 30:
            print(f"  ... and {len(bad) - 30} more", file=sys.stderr)
        print(
            "\n  /attribution promises that Pavois maps reference NUMBERS and never reproduces\n"
            "  benchmark prose. Store the identifier; put the explanation in the control's own\n"
            "  title, which is Pavois-owned.",
            file=sys.stderr,
        )
        return 1
    print("lint:norm-refs: every mapping is a reference, as /attribution claims")
    return 0


if __name__ == "__main__":
    sys.exit(main())
