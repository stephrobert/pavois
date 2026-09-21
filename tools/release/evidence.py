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

SIX STATES, NOT TWO (#351)

This used to answer ok/FAIL, and that collapsed two different things into the same word. Seven of
the nine supported systems have no campaign at all: their corpus is rendered and curated, and
nothing has ever been proved on a clean VM. Calling that FAIL is wrong, and calling it "supported"
without qualification is worse. The states are kept distinct and may not be collapsed:

  VERIFIED    the last campaign passed, on THIS corpus, inside the freshness window
  FAILED      the last campaign ran and a required stage failed
  STALE       the last campaign passed, but on another corpus or too long ago
  INCOMPLETE  a campaign exists and does not say what it proved (interrupted, no summary)
  CURATED     corpus rendered and curated, no clean-VM campaign has ever run
  UNKNOWN     nothing to go on

The LAST campaign decides, never the best one. A system that passed last week and failed last night
is FAILED. That is the point of the issue: a green result must never survive the run that broke it.

WHAT IT PUBLISHES

`--json` emits one record per system, built from an ALLOWLIST of fields, never by stripping a
denylist from the raw summary. A scan summary carries `run.target.id`, which on the maintainer's
lab is the VM's IP address, and every finding repeats it. An allowlist cannot forget to remove a
field that gets added later; a denylist can, and would publish it. A second guard re-reads the
finished record and refuses to emit anything that still looks like an address, a login or a home
directory, because the allowlist is written by hand and hands slip.

Usage:
  tools/release/evidence.py debian12 debian13 [--reports DIR]   gate: 0 iff all VERIFIED
  tools/release/evidence.py --all --json evidence.json          report: every rendered system
  tools/release/evidence.py --selftest                          the state machine, on fixtures
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

# How long a passing campaign stays current. The digest comparison below already catches OUR drift
# the instant it happens, so this window is not about the corpus: it is about the target. A Debian
# 12 image receives kernels and packages that no digest of ours can see, and a campaign from two
# months ago describes a machine that no longer exists. Thirty days is the documented window; it is
# published in every record so a reader can judge it rather than trust it.
FRESHNESS_WINDOW_DAYS = 30

VERIFIED = "VERIFIED"
FAILED = "FAILED"
STALE = "STALE"
INCOMPLETE = "INCOMPLETE"
CURATED = "CURATED"
UNKNOWN = "UNKNOWN"

# The only state that satisfies a release claim. Everything else fails the gate, including CURATED:
# a system nobody proved is not a system a release may call validated.
GATE_PASSES = {VERIFIED}


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


def summaries(log: pathlib.Path) -> list[dict]:
    """Every scan summary a campaign printed, in order.

    A campaign scans before hardening and again after the reboot, so the first and the last are the
    before/after the matrix publishes. A line that merely looks like a summary is skipped rather
    than fatal: the log is stdout, and anything may have printed into it.
    """
    out: list[dict] = []
    for line in log.read_text(errors="replace").splitlines():
        line = line.strip()
        if line.startswith('{"counts"'):
            with contextlib.suppress(json.JSONDecodeError):
                out.append(json.loads(line))
    return out


def gather(os_name: str, reports: pathlib.Path) -> dict:
    """Read from disk everything the state machine needs. No verdict is formed here."""
    profile = ROOT / "profiles" / "linux" / os_name
    reference = ROOT / "docs" / "reference" / "pavois-content" / f"{os_name}.yml"
    facts: dict = {
        "os": os_name,
        "corpus_present": profile.is_dir() and any(profile.rglob("*.rb")),
        "reference_present": reference.is_file(),
        "current_digest": dir_digest(profile) if profile.is_dir() else "",
        "campaign_id": None,
        "verdict": None,
        "run_validation_failed": False,
        "before": None,
        "after": None,
    }

    campaigns = sorted(reports.glob(f"golden-{os_name}-*/campaign.log"))
    if not campaigns:
        return facts

    # The LAST campaign, never the best one: a green run must not survive the run that broke it.
    log = campaigns[-1]
    campaign = log.parent
    text = log.read_text(errors="replace")
    facts["campaign_id"] = campaign.name
    verdicts = re.findall(r"GOLDEN PATH: (\w+)", text)
    facts["verdict"] = verdicts[-1] if verdicts else None
    facts["run_validation_failed"] = "RUN VALIDATION FAILED" in text

    facts.update(from_bundle(campaign))

    # The provenance block (ruleset digest, platform, timestamp) exists only in the summary pavois
    # prints; the bundle seals the raw InSpec reports, which do not carry it. See from_bundle().
    scans = summaries(log)
    if scans:
        facts["before"] = scans[0]
        facts["after"] = scans[-1]
    if not facts.get("evidence_source"):
        facts["evidence_source"] = "campaign log (no bundle)"
    return facts


def from_bundle(campaign: pathlib.Path) -> dict:
    """Read the campaign's own evidence bundle rather than scraping what it printed.

    `pavois harden apply --scan` seals `bundle/` at the end of a campaign: `manifest.json`
    (`pavois-evidence-bundle/v1`) with the before/after grades, the posture per class, the binary's
    own sha256 and the transition counts; `campaign-delta.json` with the control ids behind each
    transition, `pass>fail` included, which is the product's own regression list; and
    `checksums.txt` sealing all of it.

    The first version of this function parsed `campaign.log` for lines starting with `{"counts"`.
    That works and it is the wrong source: it depends on a human-readable log's shape, it cannot be
    verified, and it re-derives by hand what the bundle states. A compliance tool that publishes
    evidence should read its own evidence.

    The scan JSON is still opened for `run`: the ruleset digest that decides STALE, the exact
    platform, the timestamp. The manifest does not carry them today, which is a gap worth closing in
    the bundle writer rather than here.
    """
    bundle = campaign / "bundle"
    manifest_path = bundle / "manifest.json"
    if not manifest_path.is_file():
        return {}

    try:
        manifest = json.loads(manifest_path.read_text())
    except (json.JSONDecodeError, OSError):
        return {}

    out: dict = {
        "evidence_source": manifest.get("format", "bundle"),
        "bundle_intact": verify_checksums(bundle),
        "posture": manifest.get("posture"),
        "transitions": (manifest.get("campaign") or {}).get("transitions"),
        "regressions": (manifest.get("campaign") or {}).get("regressions"),
        "pavois_version": manifest.get("pavois_version"),
    }

    delta_path = bundle / "campaign-delta.json"
    if delta_path.is_file():
        with contextlib.suppress(json.JSONDecodeError, OSError):
            controls = json.loads(delta_path.read_text()).get("controls") or {}
            # pavois computes this itself; recomputing it from two scans would be a second opinion
            # nobody asked for, and one more thing to get wrong.
            out["regressed_controls"] = sorted(controls.get("pass>fail", []))
            out["still_failing_controls"] = sorted(controls.get("fail>fail", []))

    # Grades and counts from the manifest, which states them, rather than from a printed summary.
    for role in ("before", "after"):
        block = manifest.get(role) or {}
        if block:
            out[f"{role}_manifest"] = {
                "grade": block.get("grade"),
                "passed": block.get("passed"),
                "total": block.get("total"),
            }

    # DELIBERATELY NOT read here: the scan files the bundle seals are the RAW InSpec reports
    # (`platform`, `profiles`, `statistics`, `version`). They do not carry pavois's own provenance
    # block, so the ruleset digest that decides STALE, the exact platform string and the scan
    # timestamp exist only in the summary pavois prints, which lands in campaign.log.
    #
    # That is a gap in the bundle, not in this reader: a sealed artefact that cannot say WHICH rule
    # base produced it forces every consumer back to a log. Until the bundle writer records it,
    # `gather()` keeps taking `before`/`after` from the printed summary and this function supplies
    # everything the manifest and the delta DO state.
    return out


def verify_checksums(bundle: pathlib.Path) -> bool | None:
    """Does the bundle still hash to what it says? None when it does not say."""
    sums = bundle / "checksums.txt"
    if not sums.is_file():
        return None
    for line in sums.read_text().splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        digest, name = parts[0], parts[1].strip()
        target = bundle / name
        if not target.is_file():
            return False
        if hashlib.sha256(target.read_bytes()).hexdigest() != digest:
            return False
    return True


def advertised_version() -> str:
    """The version the site tells people to install, read from its single source.

    `site/src/data/install.ts` is that source, and `site:install-single-source` already refuses a
    page that retypes it. Reading it here rather than keeping a second copy is the same discipline:
    two places holding a version number is one place holding a stale one.
    """
    src = ROOT / "site" / "src" / "data" / "install.ts"
    if not src.is_file():
        return ""
    m = re.search(r"export const VERSION\s*=\s*'([^']+)'", src.read_text())
    return m.group(1).lstrip("v") if m else ""


ADVERTISED = advertised_version()


def tested_version(facts: dict) -> str:
    """Which pavois produced this campaign's evidence.

    `dev` is what a binary built from a checkout reports, so it doubles as the marker for "this
    campaign proved the working tree, not a release".
    """
    v = facts.get("pavois_version") or ""
    if not v:
        v = ((facts.get("after") or {}).get("run") or {}).get("tool", {}).get("version", "")
    return str(v).lstrip("v")


def recorded_digest(summary: dict | None) -> str:
    return ((summary or {}).get("run") or {}).get("ruleset", {}).get("digest", "")


def campaign_time(facts: dict) -> dt.datetime | None:
    """When the campaign's final scan ran, from the scan itself, or from the directory name."""
    stamp = ((facts.get("after") or {}).get("run") or {}).get("timestamp")
    if stamp:
        with contextlib.suppress(ValueError):
            return dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    cid = facts.get("campaign_id") or ""
    m = re.search(r"(\d{8})-(\d{6})$", cid)
    if m:
        with contextlib.suppress(ValueError):
            # `date +%Y%m%d-%H%M%S` in golden_path.sh stamps LOCAL time. Reading it as UTC put a
            # campaign two hours in the future on a CEST workstation, and the site published
            # "il y a -1 j". astimezone() on a naive value attaches the local zone, which is what
            # the stamp actually is.
            naive = dt.datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")
            return naive.astimezone()
    return None


def age_days(ran: dt.datetime | None, now: dt.datetime) -> int | None:
    """Whole days since a campaign, never negative.

    A clock that disagrees with itself is not a reason to publish a campaign that ran in the
    future. Anything from the last 24 hours reads as 0.
    """
    if ran is None:
        return None
    return max(0, (now - ran).days)


def classify(facts: dict, now: dt.datetime, window_days: int = FRESHNESS_WINDOW_DAYS) -> tuple:
    """(state, [reasons]). Pure: no disk, no clock, no network. That is what makes it testable.

    Order matters, and it is the order of how badly the evidence is missing. A campaign that says
    nothing about which corpus it measured is INCOMPLETE, never VERIFIED, because "no evidence" and
    "evidence of success" must not read the same.
    """
    if not facts.get("corpus_present"):
        return UNKNOWN, ["no rendered corpus for this system"]

    if not facts.get("campaign_id"):
        if facts.get("reference_present"):
            return CURATED, [
                "corpus rendered and curated from the pavois reference",
                "no clean-VM campaign has ever run for this system",
            ]
        return UNKNOWN, ["a corpus exists but no pavois reference does: nothing curates it"]

    where = [f"campaign {facts['campaign_id']}"]

    if facts.get("verdict") is None:
        return INCOMPLETE, where + ["the campaign never reached a verdict (interrupted?)"]
    if facts["verdict"] != "PASSED":
        return FAILED, where + [f"the campaign verdict is {facts['verdict']}"]
    if facts.get("run_validation_failed"):
        return FAILED, where + ["a scan in this campaign did not measure what it reported"]

    after = facts.get("after")
    if not after:
        return INCOMPLETE, where + ["no scan summary in the log, so nothing says which corpus ran"]

    recorded = recorded_digest(after)
    if not recorded:
        return INCOMPLETE, where + ["the scan recorded no ruleset digest (pavois too old?)"]

    # WHICH corpus a campaign must match depends on WHAT it was proving.
    #
    # A campaign run against a RELEASED binary measures the rule base embedded in that release. The
    # working tree's corpus moves on the next commit to rules.yml, and comparing the two would flip
    # all nine platforms to STALE the moment main advances, while the release they describe has not
    # changed at all. A campaign proves a (version, platform) pair, and judging it against a corpus
    # it was never asked to run is a category error.
    #
    # So: a campaign of a released version is judged self-consistent by construction, and what can
    # make it stale is its AGE, or the site advertising a different version than the one proved.
    # A campaign of the working tree keeps the digest comparison, because there the corpus on disk
    # IS the thing it claimed to measure.
    tested = tested_version(facts)
    current = facts.get("current_digest", "")
    if tested in ("", "dev") and recorded != current:
        return STALE, where + [
            "the campaign measured a DIFFERENT corpus than the working tree",
            f"  campaign: {recorded}",
            f"  current:  {current}",
            "  re-run tools/golden_path.sh " + facts["os"],
        ]
    if tested not in ("", "dev") and ADVERTISED and tested != ADVERTISED:
        return STALE, where + [
            f"the campaign proved {tested}, and the site advertises {ADVERTISED}",
            "  a verdict is about one version; re-run the campaign against the released one",
        ]

    ran = campaign_time(facts)
    if ran is None:
        return INCOMPLETE, where + ["the campaign carries no timestamp, so its age is unknown"]
    age = age_days(ran, now)
    if age > window_days:
        return STALE, where + [
            f"the campaign ran {age} days ago, past the {window_days}-day freshness window",
            "  the corpus has not moved; the target's own packages and kernel have",
        ]

    return VERIFIED, where + [
        "verdict PASSED",
        f"corpus matches ({current[:23]}...)",
        f"{age} day(s) old, within the {window_days}-day window",
    ]


# --------------------------------------------------------------------------------------------
# Publication
# --------------------------------------------------------------------------------------------

# Anything that looks like machine identity. The record is built from an allowlist, so this should
# never fire; it exists because the allowlist is written by hand. Every finding of every campaign
# carries the target's address in `run.target.id`; 203.0.113.10 stands in for it here, because a
# repository's history is exactly as public as the site this tool sanitises.
IDENTITY = [
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b"), "an IPv4 address"),
    (re.compile(r"\b(?:[0-9a-fA-F]{0,4}:){3,}[0-9a-fA-F]{0,4}\b"), "an IPv6 address"),
    (re.compile(r"[A-Za-z0-9._-]+@[A-Za-z0-9.-]+"), "a login@host"),
    (re.compile(r"/home/[A-Za-z0-9._-]+"), "a home directory"),
]


def assert_sanitized(obj) -> None:
    """Refuse to publish a record that still carries machine identity.

    Raises rather than redacts. A redaction here would hide the fact that the allowlist missed a
    field, and the next field it misses would be published quietly.
    """
    blob = json.dumps(obj)
    for pattern, what in IDENTITY:
        m = pattern.search(blob)
        if m:
            raise ValueError(f"refusing to publish: {what} in the record ({m.group(0)!r})")


def scan_facet(summary: dict | None) -> dict | None:
    """The publishable part of a scan summary, by allowlist.

    Deliberately absent: `run.target.id` (the VM's address), and every finding's `subject` and
    `message`. A control's neutral id and severity carry no identity and are the useful part.
    """
    if not summary:
        return None
    run = summary.get("run") or {}
    return {
        "grade": summary.get("grade"),
        "posture": summary.get("posture"),
        "passed": summary.get("passed"),
        "total": summary.get("total"),
        "failing_by_severity": summary.get("counts") or {},
        "qualified_passes": summary.get("qualified_passes"),
        "runtime_qualified": summary.get("runtime_qualified"),
        "platform": (run.get("target") or {}).get("platform"),
        "timestamp": run.get("timestamp"),
        "standards": (run.get("scope") or {}).get("included") or [],
        "pavois_version": (run.get("tool") or {}).get("version"),
        "pavois_digest": (run.get("tool") or {}).get("digest"),
        "ruleset_digest": (run.get("ruleset") or {}).get("digest"),
        "failing_controls": sorted(
            f.get("code", "") for f in (summary.get("findings") or []) if f.get("code")
        ),
    }


def record(facts: dict, state: str, reasons: list[str], now: dt.datetime) -> dict:
    """One platform's public row. Allowlist only, then checked."""
    ran = campaign_time(facts)
    rec = {
        "os": facts["os"],
        "state": state,
        "reasons": reasons,
        "freshness_window_days": FRESHNESS_WINDOW_DAYS,
        "generated_at": now.replace(microsecond=0).isoformat(),
        "provenance": provenance(),
        "campaign": {
            "id": facts.get("campaign_id"),
            "verdict": facts.get("verdict"),
            "ran_at": ran.replace(microsecond=0).isoformat() if ran else None,
            "age_days": age_days(ran, now),
            # Straight from the campaign's own sealed bundle, not re-derived here. `pass>fail` is
            # pavois's regression list; recomputing it from two scans would be a second opinion.
            "transitions": facts.get("transitions"),
            "regressed_controls": facts.get("regressed_controls"),
        },
        # Where these numbers come from, and whether the bundle still hashes to what it claims.
        # A reader judging VERIFIED is entitled to know it was read from a sealed artefact rather
        # than scraped out of a log.
        "evidence": {
            "source": facts.get("evidence_source"),
            "bundle_intact": facts.get("bundle_intact"),
        },
        "corpus": {
            "current_digest": facts.get("current_digest") or None,
            "campaign_digest": recorded_digest(facts.get("after")) or None,
            "matches": bool(
                facts.get("current_digest")
                and recorded_digest(facts.get("after")) == facts["current_digest"]
            ),
        },
        "before": scan_facet(facts.get("before")),
        "after": scan_facet(facts.get("after")),
    }
    assert_sanitized(rec)
    return rec


def provenance() -> dict:
    """Where this evidence was produced, and how to go and look at it.

    #351 asks for CI-generated evidence, and the campaigns run on a workstation today because no
    workflow runs them yet (#228). Recording WHERE a campaign ran is not a detail: a reader judging
    "VERIFIED" is entitled to know whether a pipeline anyone can inspect produced it, or a laptop
    nobody can. The field is derived, never typed, so it cannot flatter the result.
    """
    if os.environ.get("GITHUB_ACTIONS") == "true":
        server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
        repo = os.environ.get("GITHUB_REPOSITORY", "")
        run_id = os.environ.get("GITHUB_RUN_ID", "")
        return {
            "ran_on": "ci",
            "run_url": f"{server}/{repo}/actions/runs/{run_id}" if repo and run_id else None,
        }
    return {"ran_on": "workstation", "run_url": None}


def evidence_lost(target: pathlib.Path, records: list[dict]) -> str:
    """Would writing these records DROP evidence the published file already carries?

    The matrix is a committed, generated file: the site reads it and never regenerates it, so the
    same commit always builds the same page and the history of every verdict is in git. That only
    holds if a generation cannot quietly know less than the file it overwrites.

    It can. `reports/` is gitignored, so on any machine that did not run the campaigns this script
    finds nothing, calls all nine systems CURATED and exits 0. Nothing about that run looks wrong,
    and it would replace every VERIFIED with "nobody ever proved this". A guard that only checks
    the OUTPUT is well-formed cannot see it; this compares against what is already published.

    Returns an empty string when the write is safe, otherwise the sentence to print.
    """
    if not target.is_file():
        return ""
    try:
        old = json.loads(target.read_text())
    except (json.JSONDecodeError, OSError):
        return ""  # unreadable or absent: nothing to protect, write it

    def campaigned(platforms) -> set:
        return {p["os"] for p in platforms if (p.get("campaign") or {}).get("id")}

    was, now_ = campaigned(old.get("platforms") or []), campaigned(records)
    dropped = sorted(was - now_)
    if dropped:
        return f"{len(dropped)} platform(s) would lose their campaign: {', '.join(dropped)}"
    return ""


def rendered_systems() -> list[str]:
    base = ROOT / "profiles" / "linux"
    return sorted(p.name for p in base.iterdir() if p.is_dir())


# --------------------------------------------------------------------------------------------
# Selftest
# --------------------------------------------------------------------------------------------


def selftest() -> int:
    """The state machine and the sanitiser, on fixtures no VM can be asked to produce on demand.

    #351 asks for one test that deliberately breaks a stage and proves the public result degrades.
    There are four here, one per way a stage can break, and a witness that still passes, because a
    classifier that answers FAILED to everything degrades beautifully and means nothing.
    """
    now = dt.datetime(2026, 9, 21, tzinfo=dt.UTC)
    digest = "sha256:" + "a" * 64

    def summary(ts="2026-09-20T10:00:00Z", d=digest):
        return {
            "counts": {"high": 1},
            "grade": "B",
            "passed": 700,
            "total": 750,
            "findings": [{"code": "ssh-permitrootlogin", "subject": "203.0.113.10"}],
            "run": {
                "ruleset": {"digest": d},
                # Follows the advertised version rather than pinning one: a release bump would
                # otherwise turn the witness STALE for a version mismatch, and a fixture that
                # breaks on an unrelated edit teaches people to edit the test.
                "tool": {"version": ADVERTISED or "0.0.0"},
                "target": {"id": "203.0.113.10", "platform": "debian 12.15"},
                "timestamp": ts,
            },
        }

    good = {
        "os": "debian12",
        "corpus_present": True,
        "reference_present": True,
        "current_digest": digest,
        "campaign_id": "golden-debian12-20260920-100000",
        "verdict": "PASSED",
        "run_validation_failed": False,
        "before": summary(),
        "after": summary(),
    }

    cases = [
        ("witness: passing campaign, same corpus, fresh", good, VERIFIED),
        # The four deliberate breaks, one per stage that can fail.
        ("broken stage: the campaign verdict is FAILED", {**good, "verdict": "FAILED"}, FAILED),
        ("broken stage: interrupted before a verdict", {**good, "verdict": None}, INCOMPLETE),
        (
            "broken stage: a scan did not measure what it reported",
            {**good, "run_validation_failed": True},
            FAILED,
        ),
        (
            "broken stage: no summary, so nothing says what ran",
            {**good, "before": None, "after": None},
            INCOMPLETE,
        ),
        # Evidence that exists but does not describe the thing being released.
        (
            "corpus drift: a working-tree campaign, on another corpus",
            {**good, "current_digest": "sha256:" + "b" * 64, "pavois_version": "dev"},
            STALE,
        ),
        (
            "a RELEASED campaign is not judged on the working tree's corpus",
            {
                **good,
                "current_digest": "sha256:" + "b" * 64,
                "pavois_version": ADVERTISED or "0.0.0",
            },
            VERIFIED,
        ),
        (
            "the campaign proved a version the site no longer advertises",
            {**good, "pavois_version": "0.0.1-ancient"},
            STALE,
        ),
        (
            "age: passed on this corpus, 100 days ago",
            {**good, "after": summary(ts="2026-06-13T10:00:00Z"), "campaign_id": "golden-x"},
            STALE,
        ),
        # A campaign stamped in the future is a clock disagreeing with itself, not a reason to
        # refuse a verdict. It must not publish a negative age either; the site printed "-1 day"
        # because the directory stamp is local time and was being read as UTC.
        (
            "clock skew: the campaign timestamp is in the future",
            {**good, "after": summary(ts="2026-09-22T10:00:00Z")},
            VERIFIED,
        ),
        ("no digest recorded at all", {**good, "after": summary(d="")}, INCOMPLETE),
        # Curated is not a failure, and it is not a proof either.
        (
            "curated: rendered, referenced, never campaigned",
            {**good, "campaign_id": None, "verdict": None},
            CURATED,
        ),
        (
            "rendered but nothing curates it",
            {**good, "campaign_id": None, "verdict": None, "reference_present": False},
            UNKNOWN,
        ),
        ("nothing at all", {**good, "corpus_present": False}, UNKNOWN),
    ]

    bad = 0
    for label, facts, want in cases:
        got, _ = classify(facts, now)
        if got != want:
            print(f"  FAIL [{label}]: expected {want}, got {got}", file=sys.stderr)
            bad += 1

    # A degraded state must never be published as a pass.
    for state in (FAILED, STALE, INCOMPLETE, CURATED, UNKNOWN):
        if state in GATE_PASSES:
            print(f"  FAIL: {state} satisfies the release gate", file=sys.stderr)
            bad += 1

    # The evidence-loss guard, which is what makes a committed matrix safe to regenerate.
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        published = pathlib.Path(tmp) / "matrix.json"
        proved = [{"os": "debian12", "campaign": {"id": "golden-debian12-x"}}]
        published.write_text(json.dumps({"platforms": proved}))
        # A machine with no reports/ sees no campaign anywhere: that must be refused.
        blind = [{"os": "debian12", "campaign": {"id": None}}]
        if not evidence_lost(published, blind):
            print(
                "  FAIL: a matrix that lost every campaign was allowed to overwrite",
                file=sys.stderr,
            )
            bad += 1
        # The same evidence, or more, is not a loss.
        if evidence_lost(published, proved):
            print("  FAIL: an identical matrix was refused", file=sys.stderr)
            bad += 1
        # A file that does not exist yet is not evidence to protect.
        if evidence_lost(pathlib.Path(tmp) / "absent.json", blind):
            print("  FAIL: refused to create a matrix that did not exist", file=sys.stderr)
            bad += 1

    # The clamp itself, directly: a future campaign reads as 0 days old, never as -1.
    future = dt.datetime(2026, 9, 22, tzinfo=dt.UTC)
    if age_days(future, now) != 0:
        print(f"  FAIL: a future campaign reports {age_days(future, now)} days", file=sys.stderr)
        bad += 1

    # The sanitiser, on the exact value that appears in every real campaign.
    rec = record(good, VERIFIED, ["ok"], now)
    if "203.0.113.10" in json.dumps(rec):
        print("  FAIL: the record published the target's address", file=sys.stderr)
        bad += 1
    if (rec["after"] or {}).get("platform") != "debian 12.15":
        print(
            "  FAIL: the record dropped the platform version it is meant to publish",
            file=sys.stderr,
        )
        bad += 1

    # And the guard behind it: a record that smuggles an address back in must be refused.
    try:
        assert_sanitized({**rec, "oops": "root@203.0.113.10"})
        print("  FAIL: assert_sanitized accepted a record carrying an address", file=sys.stderr)
        bad += 1
    except ValueError:
        pass

    total = len(cases) + 12
    print(f"evidence selftest: {total - bad}/{total} checks")
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Platform verification evidence, per system.")
    ap.add_argument("systems", nargs="*", help="OS names the release claims as validated")
    ap.add_argument("--all", action="store_true", help="report every rendered system instead")
    ap.add_argument(
        "--json", metavar="FILE", help="write the machine-readable matrix here ('-' = stdout)"
    )
    ap.add_argument("--reports", default=str(ROOT / "reports"), help="where campaigns landed")
    ap.add_argument(
        "--allow-evidence-loss",
        action="store_true",
        help="write even when the new matrix knows less than the file it replaces",
    )
    ap.add_argument("--selftest", action="store_true", help="run the state machine on fixtures")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    systems = rendered_systems() if args.all else args.systems
    if not systems:
        ap.error("name at least one system, or pass --all")

    now = dt.datetime.now(dt.UTC)
    records = []
    failures = 0
    # With `--json -` the JSON owns stdout, so the human report moves to stderr. A caller piping
    # this into a parser must receive JSON and nothing else; mixing the two is how a driver ends up
    # parsing a status line as a record.
    report = sys.stderr if args.json == "-" else sys.stdout
    for os_name in systems:
        facts = gather(os_name, pathlib.Path(args.reports))
        state, reasons = classify(facts, now)
        records.append(record(facts, state, reasons, now))
        print(f"  {state:<10} {os_name}", file=report)
        for r in reasons:
            print(f"       {r}", file=report)
        if state not in GATE_PASSES:
            failures += 1

    if args.json:
        payload = {
            "generated_at": now.replace(microsecond=0).isoformat(),
            "freshness_window_days": FRESHNESS_WINDOW_DAYS,
            "states": [VERIFIED, FAILED, STALE, INCOMPLETE, CURATED, UNKNOWN],
            "platforms": records,
        }
        assert_sanitized(payload)
        text = json.dumps(payload, indent=2, sort_keys=False) + "\n"
        if args.json == "-":
            sys.stdout.write(text)
        else:
            target = pathlib.Path(args.json)
            lost = evidence_lost(target, records)
            if lost and not args.allow_evidence_loss:
                print(
                    f"\nevidence: REFUSING to write {args.json}.\n"
                    f"  {lost}\n"
                    "  `reports/` is gitignored and lives on the machine that ran the campaigns.\n"
                    "  Regenerating where it is absent gives an all-CURATED matrix, which would\n"
                    "  erase every proved platform while looking like a clean generation.\n"
                    "  Run the campaigns, or pass --allow-evidence-loss if the loss is intended.",
                    file=sys.stderr,
                )
                return 1
            target.write_text(text)
            print(f"\nwrote {args.json}: {len(records)} platform(s)")

    # --all is a report, not a gate: it is expected to contain CURATED systems.
    return 0 if args.all else (1 if failures else 0)


if __name__ == "__main__":
    sys.exit(main())
