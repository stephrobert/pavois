# /// script
# requires-python = ">=3.10"
# dependencies = ["fastmcp", "pyyaml"]
# ///
"""pavois norm studio — an MCP server that surfaces the OFFICIAL standards sources and exploits
the reference documents, so pavois's rule base stays the best-sourced reference in the field.

It is the content engine behind the product plan: it watches the authorities (SSG releases,
ansible-lockdown <OS>-CIS, cyber.gouv.fr, NIST OSCAL, Wazuh SCA), diffs their CURRENT versions
against pavois's recorded baseline (docs/reference/norms.yml), and extracts structured rules from
a source document on demand. Run:  uv run --with fastmcp tools/norm_studio/server.py
"""
import base64
import html
import re
import subprocess
from pathlib import Path

import yaml
from fastmcp import FastMCP

ROOT = Path(__file__).resolve().parents[2]
CATALOGUE = ROOT / "docs" / "reference" / "norms.yml"
SSG_CACHE = Path("/tmp/oscap-analysis/ssg")

# CIS implementation repos per OS (the authority that declares the implemented benchmark version).
AL_REPO = {
    "debian12": "DEBIAN12-CIS", "debian13": "DEBIAN13-CIS",
    "ubuntu2204": "UBUNTU22-CIS", "ubuntu2404": "UBUNTU24-CIS",
    "rhel8": "RHEL8-CIS", "rhel9": "RHEL9-CIS", "almalinux9": "RHEL9-CIS",
}

_REF_CACHE: dict = {}   # os -> parsed reference rules (read once, not per rule)
_DS_CACHE: dict = {}    # os -> SSG datastream XML (multi-MB; read once, not per rule)

mcp = FastMCP("pavois-norm-studio")


# ---- source helpers (plain functions, unit-testable without the MCP transport) ----------------
def _catalogue() -> dict:
    return yaml.safe_load(CATALOGUE.read_text())


def _gh_content(path: str) -> str:
    out = subprocess.run(["gh", "api", path, "--jq", ".content"],
                         capture_output=True, text=True).stdout.strip()
    return base64.b64decode(out).decode("utf-8", "ignore") if out else ""


def _al_benchmark_version(repo: str) -> str | None:
    body = _gh_content(f"repos/ansible-lockdown/{repo}/contents/README.md")
    m = re.search(r"Benchmark[^0-9]*v?(\d+\.\d+\.\d+)", body, re.I)
    return m.group(1) if m else None


def _al_rules(repo: str) -> set[str]:
    body = _gh_content(f"repos/ansible-lockdown/{repo}/contents/defaults/main.yml")
    return {m.replace("rule_", "").replace("_", ".")
            for m in re.findall(r"rule_\d+(?:_\d+)+", body)}


def _ssg_cis(os_name: str) -> set[str]:
    ds = SSG_CACHE / f"ssg-{os_name}-ds.xml"
    if not ds.exists():
        return set()
    xml = ds.read_text(encoding="utf-8")
    secs = set(re.findall(r"cisecurity[^>]*>(\d+(?:\.\d+)+)<", xml))
    return {s for s in secs if not any(o != s and o.startswith(s + ".") for o in secs)}


def _check_updates(os_filter: str = "") -> dict:
    cat = _catalogue()
    bv = cat["standards"]["cis"]["benchmark_version"]
    targets = [os_filter] if os_filter else [k for k in bv if AL_REPO.get(k)]
    drift = []
    for o in targets:
        repo = AL_REPO.get(o)
        if not repo:
            continue
        recorded = (bv.get(o) or {}).get("version")
        live = _al_benchmark_version(repo)
        drift.append({"os": o, "norm": "cis", "recorded": recorded, "live": live,
                      "update_available": bool(live and recorded and live != recorded)})
    ssg_latest = subprocess.run(
        ["gh", "release", "view", "--repo", "ComplianceAsCode/content", "--json", "tagName",
         "--jq", ".tagName"], capture_output=True, text=True).stdout.strip()
    return {"cis_per_os": drift, "ssg_latest_release": ssg_latest, "norms": _check_norm_versions()}


def _check_norm_versions() -> list:
    """Recorded-vs-live version of the NON-CIS standards, from machine-readable sources."""
    cat = _catalogue()["standards"]
    out = []

    # ANSSI-BP-028 — cyber.gouv.fr is JS-rendered/unscrapable; ComplianceAsCode anssi.yml tracks
    # the implemented ANSSI version reliably.
    anssi = _gh_content("repos/ComplianceAsCode/content/contents/controls/anssi.yml")
    m = re.search(r"^version:\s*'?\"?([\d.]+)", anssi, re.M)
    rec = cat["bp28"]["version"]
    out.append({"norm": "bp28", "recorded": rec, "live": m.group(1) if m else None,
                "source": "ComplianceAsCode/controls/anssi.yml",
                "update_available": bool(m and m.group(1) != rec)})

    # NIST SP 800-53 — highest revision directory published in the NIST OSCAL content repo.
    names = subprocess.run(
        ["gh", "api", "repos/usnistgov/oscal-content/contents/nist.gov/SP800-53", "--jq", ".[].name"],
        capture_output=True, text=True).stdout
    revs = sorted(int(x[3:]) for x in re.findall(r"rev\d+", names))
    live = f"Rev {revs[-1]}" if revs else None
    recn = cat["nist-800-53"]["version"]
    out.append({"norm": "nist-800-53", "recorded": recn, "live": live,
                "source": "usnistgov/oscal-content SP800-53",
                "update_available": bool(live and live != recn)})

    # PCI-DSS — ComplianceAsCode controls/pcidss_4.yml tracks the implemented PCI-DSS version
    # (machine-readable; cyber.gouv/pcisecuritystandards.org are not).
    pci = _gh_content("repos/ComplianceAsCode/content/contents/controls/pcidss_4.yml")
    mp = re.search(r"^version:\s*'?\"?([\d.]+)", pci, re.M)
    recp = cat["pci-dss"]["version"]
    out.append({"norm": "pci-dss", "recorded": recp, "live": mp.group(1) if mp else None,
                "source": "ComplianceAsCode/controls/pcidss_4.yml",
                "update_available": bool(mp and mp.group(1) != recp)})
    return out


def _txt(s: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", s))).strip()


def _ssg_rule_detail(os_name: str, ssg_id: str) -> dict | None:
    """Extract the rich, authoritative content for one SSG rule: title, description, rationale,
    references classified by norm, and BOTH remediations (bash + ansible)."""
    ds = SSG_CACHE / f"ssg-{os_name}-ds.xml"
    if not ds.exists() or not ssg_id:
        return None
    if os_name not in _DS_CACHE:
        _DS_CACHE[os_name] = ds.read_text(encoding="utf-8")
    xml = _DS_CACHE[os_name]
    m = re.search(rf'<[\w.:-]*Rule[^>]*id="[^"]*_rule_{re.escape(ssg_id)}"[\s\S]*?</[\w.:-]*Rule>', xml)
    if not m:
        return None
    blk = m.group(0)

    def tag(t: str) -> str | None:
        mm = re.search(rf"<[\w.:-]*{t}[^>]*>([\s\S]*?)</[\w.:-]*{t}>", blk)
        return _txt(mm.group(1)) if mm else None

    refs: dict[str, list] = {}
    for href, val in re.findall(r'<[\w.:-]*reference[^>]*href="([^"]+)"[^>]*>([^<]+)<', blk):
        val = val.strip()
        if "cisecurity" in href and re.match(r"^\d+(\.\d+)+$", val):
            refs.setdefault("cis", []).append(val)
        elif "ssi.gouv" in href or "anssi" in href.lower():
            refs.setdefault("bp28", []).append(val)
        elif "nist" in href:
            refs.setdefault("nist", []).append(val)
        elif "disa" in href or "stigid" in href.lower():
            refs.setdefault("stig", []).append(val)
        elif "pci" in href.lower():
            refs.setdefault("pci-dss", []).append(val)
    refs = {k: sorted(set(v)) for k, v in refs.items()}

    fixes: dict[str, str] = {}
    for sysid, body in re.findall(r'<[\w.:-]*fix\b[^>]*system="([^"]+)"[^>]*>([\s\S]*?)</[\w.:-]*fix>', blk):
        kind = "ansible" if "ansible" in sysid else "bash" if sysid.endswith(":sh") else sysid
        fixes[kind] = html.unescape(re.sub(r"<[^>]+>", "", body)).strip()[:6000]

    sev = re.search(r'<[\w.:-]*Rule[^>]*\bseverity="([^"]+)"', blk)
    warns = [_txt(w) for w in re.findall(r"<[\w.:-]*warning[^>]*>([\s\S]*?)</[\w.:-]*warning>", blk)]

    return {"title": tag("title"), "description": tag("description"), "rationale": tag("rationale"),
            "severity": sev.group(1) if sev else None, "warnings": warns,
            "references": refs, "remediation": fixes}


def _control_detail(os_name: str, rule: str) -> dict:
    if os_name not in _REF_CACHE:
        _REF_CACHE[os_name] = yaml.safe_load(
            (ROOT / "docs" / "reference" / "pavois-content" / f"{os_name}.yml").read_text())["rules"]
    ref = _REF_CACHE[os_name]
    cid, ctrl = None, None
    if rule in ref:
        cid, ctrl = rule, ref[rule]
    else:                                              # resolve a CIS number -> pavois control
        for k, e in ref.items():
            cv = (e.get("norms") or {}).get("cis")
            if rule in [str(x) for x in (cv if isinstance(cv, list) else [cv]) if x]:
                cid, ctrl = k, e
                break
    if not ctrl:
        return {"error": f"no pavois control matches {rule!r} for {os_name}"}
    ssg_id = ctrl.get("ssg")
    return {
        "os": os_name, "control_id": cid, "ssg_id": ssg_id,
        "pavois": {"title": ctrl.get("title"), "domain": ctrl.get("domain"),
                    "severity": ctrl.get("severity"), "check": ctrl.get("check"),
                    "norms": ctrl.get("norms"), "remediation": ctrl.get("remediation")},
        "authoritative_content": _ssg_rule_detail(os_name, ssg_id),
    }


# ---- MCP tools (thin wrappers over the helpers) -----------------------------------------------
@mcp.tool()
def norm_catalogue() -> dict:
    """pavois's norm catalogue baseline: every standard (CIS per-OS, ANSSI-BP-028, NIST 800-53/171,
    PCI-DSS, STIG) with the version pavois targets, its authority and source. The known-good
    reference the watcher compares the live sources against."""
    return _catalogue()


@mcp.tool()
def list_sources() -> dict:
    """The authoritative machine-readable sources pavois validates each norm against (the >=2-
    independent-sources rule). Use these to surface or cross-check standard content."""
    return {
        "cis": ["ComplianceAsCode SSG datastream", "ansible-lockdown <OS>-CIS"],
        "bp28": ["cyber.gouv.fr (ANSSI-BP-028)", "ComplianceAsCode controls/anssi.yml"],
        "nist-800-53": ["NIST OSCAL (usnistgov/oscal-content)", "ComplianceAsCode SSG",
                        "intuitem/ciso-assistant (nist-sp-800-53-rev5 framework — validate_mappings)"],
        "nist-800-171": ["NIST SP 800-171", "Wazuh SCA (nist_800_171)"],
        "pci-dss": ["intuitem/ciso-assistant (pcidss-4_0 framework — canonical requirements)",
                    "ComplianceAsCode pcidss_4.yml (version)", "Wazuh SCA (pci_dss)"],
        "multi_framework": ["Wazuh SCA — iso_27001/hipaa/gdpr/nis2/cmmc/fedramp"],
    }


@mcp.tool()
def check_updates(os: str = "") -> dict:
    """Check what drifted vs pavois's recorded baseline (norms.yml): the CURRENT CIS benchmark
    version per OS (ansible-lockdown) + the latest SSG release, AND the non-CIS standards under
    `norms` — ANSSI-BP-028 (ComplianceAsCode anssi.yml), NIST 800-53 (the OSCAL revision dirs),
    PCI-DSS (manual). Each entry carries recorded vs live + update_available. The norm-watcher core."""
    return _check_updates(os)


def _ssg_cis(os_name: str) -> set:
    ds = SSG_CACHE / f"ssg-{os_name}-ds.xml"
    if not ds.exists():
        return set()
    if os_name not in _DS_CACHE:
        _DS_CACHE[os_name] = ds.read_text(encoding="utf-8")
    secs = set(re.findall(r"cisecurity[^>]*>(\d+(?:\.\d+)+)<", _DS_CACHE[os_name]))
    return {s for s in secs if not any(o != s and o.startswith(s + ".") for o in secs)}


def _pavois_cis(os_name: str) -> set:
    if os_name not in _REF_CACHE:
        _REF_CACHE[os_name] = yaml.safe_load(
            (ROOT / "docs" / "reference" / "pavois-content" / f"{os_name}.yml").read_text())["rules"]
    out = set()
    for e in _REF_CACHE[os_name].values():
        v = (e.get("norms") or {}).get("cis")
        for x in (v if isinstance(v, list) else [v]):
            if x:
                out.add(str(x))
    return out


def _scrape_diff(os_name: str) -> dict:
    al = _al_rules(AL_REPO[os_name]) if AL_REPO.get(os_name) else set()
    ssg = _ssg_cis(os_name)
    ck = _pavois_cis(os_name)
    union = ssg | al
    consensus = (ssg & al) if (ssg and al) else union
    return {
        "os": os_name,
        "benchmark_version": (_catalogue()["standards"]["cis"]["benchmark_version"].get(os_name) or {}).get("version"),
        "sources": {"ssg": len(ssg), "ansible_lockdown": len(al)},
        "consensus": len(consensus),
        "pavois_covers": len(consensus & ck),
        "missing_in_pavois": sorted(consensus - ck, key=lambda s: [int(x) for x in s.split(".")]),
        "suspect_pavois_mappings": sorted(ck - union - {""}),
    }


@mcp.tool()
def scrape_diff(os: str) -> dict:
    """Scrape the live CIS benchmark (ansible-lockdown <OS>-CIS + the SSG datastream) and diff it
    against pavois's reference. Returns the benchmark version, source counts, consensus coverage,
    the CIS rules the benchmark has that pavois is MISSING (enrichment targets), and pavois
    mappings in NEITHER source (suspects). The scrape+check core of the watch→scrape→enrich loop."""
    return _scrape_diff(os)


def _cis_to_ssg(os_name: str) -> dict:
    ds = SSG_CACHE / f"ssg-{os_name}-ds.xml"
    if not ds.exists():
        return {}
    if os_name not in _DS_CACHE:
        _DS_CACHE[os_name] = ds.read_text(encoding="utf-8")
    idx = {}
    for blk in re.split(r"(?=<[\w.:-]*Rule\s)", _DS_CACHE[os_name])[1:]:
        m = re.search(r'id="[^"]*content_rule_([\w-]+)"', blk)
        if not m:
            continue
        end = re.search(r"</[\w.:-]*Rule>", blk)
        seg = blk[: end.start()] if end else blk
        for href, val in re.findall(r'<[\w.:-]*reference[^>]*href="([^"]+)"[^>]*>([^<]+)</', seg):
            v = val.strip()
            if "cisecurity" in href and re.match(r"^\d+(\.\d+)+$", v):
                idx.setdefault(v, m.group(1))
    return idx


def _propose_enrichment(os_name: str, limit: int = 12) -> dict:
    diff = _scrape_diff(os_name)
    idx = _cis_to_ssg(os_name)
    out = []
    for cis in diff["missing_in_pavois"][:limit]:
        ssg_id = idx.get(cis)
        d = _ssg_rule_detail(os_name, ssg_id) if ssg_id else None
        out.append({
            "cis": cis,
            "ssg_id": ssg_id,
            "title": d.get("title") if d else None,
            "severity": d.get("severity") if d else None,
            "rationale": ((d.get("rationale") or "")[:240]) if d else None,
            "references": d.get("references") if d else {},
            "needs": "a neutral pavois id + an EFFECTIVE-config check + a harden remediation plan",
        })
    return {"os": os_name, "missing_total": len(diff["missing_in_pavois"]),
            "benchmark_version": diff["benchmark_version"], "proposals": out}


@mcp.tool()
def propose_enrichment(os: str, limit: int = 12) -> dict:
    """For the CIS rules pavois is MISSING vs the live benchmark, scrape each one's SSG detail
    (title, severity, rationale, references) and return enrichment proposals — the raw material to
    add a neutral pavois rule. Flags what pavois must still author: the effective-config check
    and the harden remediation (which SSG can't provide). The enrich half of the pipeline."""
    return _propose_enrichment(os, limit)


_CISO_PCI: dict = {}


def _ciso_pci_reqs() -> dict:
    if not _CISO_PCI:
        body = _gh_content(
            "repos/intuitem/ciso-assistant-community/contents/backend/library/libraries/pcidss-4_0.yaml")
        d = yaml.safe_load(body) if body else {}
        fw = (d.get("objects") or {}).get("framework") or {}
        nodes = fw.get("requirement_nodes") or []
        mver = re.search(r"\d+\.\d+", str(fw.get("name") or d.get("name") or ""))
        _CISO_PCI["version"] = mver.group(0) if mver else "4.0"
        _CISO_PCI["all"] = {str(n["ref_id"]).lower() for n in nodes if n.get("ref_id")}
        _CISO_PCI["assessable"] = sum(1 for n in nodes if n.get("assessable"))
    return _CISO_PCI


def _pavois_pci(os_name: str) -> set:
    if os_name not in _REF_CACHE:
        _REF_CACHE[os_name] = yaml.safe_load(
            (ROOT / "docs" / "reference" / "pavois-content" / f"{os_name}.yml").read_text())["rules"]
    out = set()
    for e in _REF_CACHE[os_name].values():
        v = (e.get("norms") or {}).get("pci-dss")
        for x in (v if isinstance(v, list) else [v]):
            if x:
                out.add(re.sub(r"^req-?", "", str(x).strip().lower()))
    return out


def _pci_validate(os_name: str) -> dict:
    fw = _ciso_pci_reqs()
    refs = fw["all"]
    ck = _pavois_pci(os_name)
    suspect = sorted(ck - refs)
    return {
        "os": os_name,
        "source": "intuitem/ciso-assistant pcidss-4_0.yaml",
        "pci_version": fw.get("version"),
        "framework_requirements": len(refs),
        "assessable": fw["assessable"],
        "pavois_pci_tags": len(ck),
        "valid": len(ck) - len(suspect),
        "suspect": suspect,
    }


@mcp.tool()
def pci_validate(os: str) -> dict:
    """Cross-validate pavois's PCI-DSS tags against the canonical PCI-DSS 4.0 framework from
    intuitem/ciso-assistant (373 requirement nodes). Returns which pavois pci-dss tags are valid
    PCI requirements and which are SUSPECT (absent from the official framework) — densifying the
    PCI side beyond the SSG/Wazuh references."""
    return _pci_validate(os)


_CISO_FW_FILE = {"pci-dss": "pcidss-4_0.yaml", "nist": "nist-sp-800-53-rev5.yaml"}
_CISO_FW: dict = {}


def _ciso_framework(file: str) -> dict:
    """Canonical requirement ref_ids of a ciso-assistant framework, fetched RAW (some are >1 MB,
    too large for the GitHub contents API)."""
    if file not in _CISO_FW:
        raw = subprocess.run(
            ["curl", "-sL", "-m", "40",
             "https://raw.githubusercontent.com/intuitem/ciso-assistant-community/main/"
             f"backend/library/libraries/{file}"], capture_output=True, text=True).stdout
        d = yaml.safe_load(raw) if raw else {}
        fw = (d.get("objects") or {}).get("framework") or {}
        nodes = fw.get("requirement_nodes") or []
        _CISO_FW[file] = {"name": fw.get("name"),
                          "refs": {str(n["ref_id"]).lower() for n in nodes if n.get("ref_id")},
                          "assessable": sum(1 for n in nodes if n.get("assessable"))}
    return _CISO_FW[file]


def _pavois_norm_tags(os_name: str, norm: str) -> set:
    if os_name not in _REF_CACHE:
        _REF_CACHE[os_name] = yaml.safe_load(
            (ROOT / "docs" / "reference" / "pavois-content" / f"{os_name}.yml").read_text())["rules"]
    out = set()
    for e in _REF_CACHE[os_name].values():
        v = (e.get("norms") or {}).get(norm)
        for x in (v if isinstance(v, list) else [v]):
            if x:
                out.add(str(x))
    return out


def _normalize_ref(norm: str, tag: str) -> str:
    if norm == "pci-dss":
        return re.sub(r"^req-?", "", tag.strip().lower())
    if norm == "nist":
        return re.sub(r"[ (].*", "", tag).strip().lower()   # base control: AC-17(a) -> ac-17
    return tag.strip().lower()


def _framework_validate(os_name: str, norm: str) -> dict:
    file = _CISO_FW_FILE.get(norm)
    if not file:
        return {"error": f"no ciso-assistant framework for {norm!r} (have {list(_CISO_FW_FILE)})"}
    fw = _ciso_framework(file)
    raw = _pavois_norm_tags(os_name, norm)
    if norm == "nist":
        considered = {t for t in raw if re.match(r"^[A-Z]{2}-\d", t)}   # 800-53 form only
        other = sorted(raw - considered)                                # 800-171 etc.
    else:
        considered, other = raw, []
    suspect = sorted(t for t in considered if _normalize_ref(norm, t) not in fw["refs"])
    res = {"os": os_name, "norm": norm, "source": f"intuitem/ciso-assistant {file}",
           "framework": fw["name"], "requirements": len(fw["refs"]), "assessable": fw["assessable"],
           "pavois_tags": len(considered), "valid": len(considered) - len(suspect), "suspect": suspect}
    if other:
        res["other_publication"] = {"count": len(other),
                                    "note": "different NIST publication (e.g. 800-171)", "examples": other[:8]}
    return res


@mcp.tool()
def validate_mappings(os: str, norm: str) -> dict:
    """Cross-validate pavois's mappings for a standard (norm = 'pci-dss' or 'nist') against the
    canonical framework from intuitem/ciso-assistant. Returns valid vs SUSPECT tags (absent from the
    official framework). For nist, only 800-53-form tags are checked; 800-171 (dotted) is reported
    under other_publication. Densifies pavois's mapping QA beyond the SSG/Wazuh references."""
    return _framework_validate(os, norm)


@mcp.tool()
def get_benchmark_rules(os: str, source: str = "ansible_lockdown") -> dict:
    """Exploit a reference document: extract the structured CIS rule list for an OS from a source
    ('ansible_lockdown' = <OS>-CIS repo, or 'ssg' = the SSG datastream cache). Returns the sorted
    rule numbers + count — the raw material to enrich or cross-check pavois's mappings."""
    if source == "ssg":
        rules = _ssg_cis(os)
    else:
        repo = AL_REPO.get(os)
        rules = _al_rules(repo) if repo else set()
    return {"os": os, "source": source, "count": len(rules),
            "rules": sorted(rules, key=lambda s: [int(x) for x in s.split(".")] if re.match(r"^\d", s) else [9999])}


def _draft_rule_page(os_name: str, rule: str) -> dict:
    d = _control_detail(os_name, rule)
    if "error" in d:
        return d
    ac = d.get("authoritative_content") or {}
    cisv = (_catalogue()["standards"]["cis"]["benchmark_version"].get(os_name) or {}).get("version")
    title_en = ac.get("title") or d["pavois"]["title"] or d["control_id"]
    rationale_en = (ac.get("rationale") or "").strip()
    sev = ac.get("severity")
    entry = {                                          # content-collection entry for the Astro site
        "id": d["control_id"], "os": os_name, "domain": d["pavois"].get("domain"),
        "severity": sev if sev in ("low", "medium", "high") else "unknown",
        "norms": d["pavois"]["norms"] or {},
        "norm_versions": {"cis": cisv} if cisv else {},
        "check": d["pavois"]["check"] or [],
        "references": ac.get("references", {}),
        # pavois's OWN remediation (its `harden` engine plan) — NOT SSG's bash/ansible fixes.
        "remediation": d["pavois"].get("remediation") or {},
        "title": {"en": title_en, "fr": title_en},     # fr to be filled by a translation pass
        "needs_translation": ["title.fr"],
    }
    if rationale_en:
        entry["rationale"] = {"en": rationale_en, "fr": rationale_en}
        entry["needs_translation"].append("rationale.fr")
    return entry


@mcp.tool()
def draft_rule_page(os: str, rule: str) -> dict:
    """Serialize a control into a content-collection entry for the bilingual hardening site:
    merges pavois's check + norms (with benchmark version) and the SSG title/rationale/references/
    remediation into one JSON record. English is filled from the sources; the fr fields are echoed
    and listed in `needs_translation` for a translation pass (the "best content" step)."""
    return _draft_rule_page(os, rule)


@mcp.tool()
def get_control_detail(os: str, rule: str) -> dict:
    """Exploit the reference documents for ONE control: given an OS and a pavois control id OR a
    CIS section number, return pavois's effective-config check + remediation + norm mappings,
    merged with the authoritative SSG content (title, description, rationale, references by norm,
    bash AND ansible remediation). This is the rich per-rule material for the hardening site."""
    return _control_detail(os, rule)


if __name__ == "__main__":
    mcp.run()
