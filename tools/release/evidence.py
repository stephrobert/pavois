#!/usr/bin/env python3
"""Did a golden-path campaign prove THIS corpus, on the systems the release claims?

A compliance scanner's release note is a claim about machines: "validated on Debian 12 and 13".
The claim is only worth what the last campaign measured, and a campaign measures the corpus that
existed when it ran. Those two can drift apart in half an hour, and they did: the first Debian 12
campaign finished at 13:10 on a corpus whose command-wrapping defect was fixed at 13:40. It
reported a clean two-pass convergence for four controls that had never run a single one of their
commands as root.

Nothing in the campaign log says "stale". The scan does record the ruleset content digest, so the
comparison is available, it was simply never made. This makes it.

Usage:  tools/release/evidence.py debian12 debian13 [--reports DIR]
Exit:   0 every named system has a passing campaign on the current corpus, 1 otherwise.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def dir_digest(directory: pathlib.Path) -> str:
    """The same content hash pavois stamps into every scan (go/cmd/provenance.go: dirDigest).

    Relative path, NUL, content, NUL, in sorted order. Reimplemented rather than shelled out to
    because the binary needs a target to scan before it will print one, and a preflight must not
    need a machine.
    """
    files = sorted(
        (p.relative_to(directory).as_posix(), p) for p in directory.rglob("*") if p.is_file()
    )
    h = hashlib.sha256()
    for rel, path in files:
        h.update(rel.encode())
        h.update(b"\0")
        h.update(path.read_bytes())
        h.update(b"\0")
    return "sha256:" + h.hexdigest()


def last_summary(log: pathlib.Path) -> dict | None:
    """The final scan summary a campaign printed on stdout, which carries the provenance block."""
    found = None
    for line in log.read_text(errors="replace").splitlines():
        line = line.strip()
        if line.startswith('{"counts"'):
            # A campaign log is stdout plus whatever the tools printed into it, so a line that
            # merely looks like the summary is skipped rather than fatal.
            with contextlib.suppress(json.JSONDecodeError):
                found = json.loads(line)
    return found


def check(os_name: str, reports: pathlib.Path) -> tuple[bool, list[str]]:
    notes: list[str] = []
    campaigns = sorted(reports.glob(f"golden-{os_name}-*/campaign.log"))
    if not campaigns:
        return False, [f"no golden-path campaign found under {reports}/golden-{os_name}-*"]
    log = campaigns[-1]
    text = log.read_text(errors="replace")
    notes.append(f"campaign {log.parent.name}")

    verdicts = re.findall(r"GOLDEN PATH: (\w+)", text)
    if not verdicts:
        return False, notes + ["the campaign never reached a verdict (interrupted?)"]
    if verdicts[-1] != "PASSED":
        return False, notes + [f"the campaign verdict is {verdicts[-1]}"]
    notes.append("verdict PASSED")

    summary = last_summary(log)
    if not summary:
        return False, notes + ["no scan summary in the log, so nothing says which corpus ran"]

    recorded = (summary.get("run") or {}).get("ruleset", {}).get("digest", "")
    if not recorded:
        return False, notes + ["the scan recorded no ruleset digest (pavois too old?)"]

    profile = ROOT / "profiles" / "linux" / os_name
    if not profile.is_dir():
        return False, notes + [
            f"{profile} does not exist: render the corpus first (mise run render)"
        ]
    current = dir_digest(profile)

    if recorded != current:
        return False, notes + [
            "the campaign measured a DIFFERENT corpus than the one being released",
            f"  campaign: {recorded}",
            f"  current:  {current}",
            "  re-run tools/golden_path.sh " + os_name,
        ]
    notes.append(f"corpus matches ({current[:23]}...)")

    # A passing campaign whose final scan was not itself trustworthy proves nothing, and the
    # campaign already answers this: validate_run.py ran after every scan.
    if "RUN VALIDATION FAILED" in text:
        return False, notes + ["a scan in this campaign did not measure what it reported"]

    return True, notes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("systems", nargs="+", help="OS names the release claims as validated")
    ap.add_argument("--reports", default=str(ROOT / "reports"), help="where campaigns landed")
    args = ap.parse_args()

    reports = pathlib.Path(args.reports)
    failures = 0
    for os_name in args.systems:
        ok, notes = check(os_name, reports)
        head = "ok  " if ok else "FAIL"
        print(f"  {head} {os_name}")
        for n in notes:
            print(f"       {n}")
        if not ok:
            failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
