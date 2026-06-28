#!/usr/bin/env python3
"""Render the pavois reference (docs/reference/pavois-content/<os>.yml) into the
InSpec corpus (profiles/linux/<os>/controls/*.rb) the scanner executes. The
reference is the SOURCE OF TRUTH; this is its only consumer for scanning. No
datastream involved.

Usage: tools/render_reference.py <os> [<out_dir>]
  default out_dir = profiles/linux/<os>/controls
"""
import re
import sys
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NORMS = ("bp28", "cis", "pci-dss", "nist", "stig")


def _excl_groups():
    p = ROOT / "docs" / "reference" / "exclusivity.yml"
    if not p.exists():
        return {}
    return (yaml.safe_load(p.read_text(encoding="utf-8")) or {}).get("groups", {})


EXCL = _excl_groups()  # mutually-exclusive "one of" groups (firewall/logging/time-sync)


def _rb(s):
    if isinstance(s, dict):
        return "{" + ", ".join(_rb(k)+" => "+_rb(v) for k,v in s.items()) + "}"
    if isinstance(s, (list, tuple)):  # merged rules keep distinct per-norm values as an array
        return "[" + ", ".join(_rb(x) for x in s) + "]"
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'") + "'"


def _tag(k, v):
    # 'pci-dss' (and any non-identifier key) needs the arrow form
    return f"tag({_rb(k)} => {_rb(v)})" if not k.isidentifier() else f"tag {k}: {_rb(v)}"


def render_control(cid, e):
    out = [f"control {_rb(cid)} do", f"  impact {e['impact']}", f"  title {_rb(e['title'])}"]
    if e.get("note"):
        out.append(f"  desc {_rb(e['note'])}")
    if e.get("domain"):
        out.append(f"  tag domain: {_rb(e['domain'])}")
    if e.get("evidence_type"):
        out.append(f"  tag evidence: {_rb(e['evidence_type'])}")
    if e.get("reboot_survivable"):
        out.append(f"  tag reboot: {_rb(e['reboot_survivable'])}")
    if e.get("requires_companion_control"):
        out.append(f"  tag companion: {_rb(e['requires_companion_control'])}")
    for k in NORMS:
        if k in e.get("norms", {}):
            out.append("  " + _tag(k, e["norms"][k]))
    for k in ("bp28", "cis"):
        if k in e.get("levels", {}):
            out.append(f"  tag level_{k}: {_rb(e['levels'][k])}")
    if "merge_group" in e:
        out.append(f"  tag merge_group: {_rb(e['merge_group'])}")
    if "posture" in e:
        out.append(f"  tag posture: {_rb(e['posture'])}")
    if e.get("ssg"):
        out.append(f"  tag ssg: {_rb(e['ssg'])}")
    # Mutual exclusivity ("one of"): a per-tech member is N/A when ANOTHER option in its
    # group already satisfies the requirement — `only_if` skips the control (-> n/a) unless
    # this tech is actually needed. The group's "is any active?" check comes from
    # exclusivity.yml. E.g. with rsyslog running, service-syslogng-enabled is N/A, not a gap.
    grp = e.get("exclusive_group")
    if grp and grp in EXCL:
        out.append(f"  tag exclusive_group: {_rb(grp)}")
        # Build the guard from the group's option services using the InSpec `service`
        # resource (reliable — no shell/PATH dependency): skip (-> n/a) if ANY option is
        # already running, since the "one of" requirement is then met by another tech.
        svcs = [o.get("service") for o in EXCL[grp].get("options", {}).values() if o.get("service")]
        cond = " || ".join(f"service({_rb(s)}).running?" for s in svcs) or "false"
        out.append(
            f"  only_if({_rb('n/a: another option in the ' + grp + ' group is active')}) "
            + "{ not (" + cond + ") }")
    out += ["  " + l for l in e.get("check", [])]
    out.append("end\n")
    return "\n".join(out)


def slug(domain):
    s = re.sub(r"[^a-z0-9]+", "_", (domain or "misc").lower()).strip("_")
    return s or "misc"


def main(os_name, out_dir=None):
    src = ROOT / "docs" / "reference" / "pavois-content" / f"{os_name}.yml"
    ref = yaml.safe_load(src.read_text(encoding="utf-8"))["rules"]
    out = Path(out_dir) if out_dir else ROOT / "profiles" / "linux" / os_name / "controls"
    out.mkdir(parents=True, exist_ok=True)
    groups = {}
    for cid in sorted(ref):
        groups.setdefault(slug(ref[cid]["domain"]), []).append(render_control(cid, ref[cid]))
    for f in out.glob("*.rb"):
        f.unlink()
    for name, ctrls in sorted(groups.items()):
        (out / f"{name}.rb").write_text(
            f"# Rendered from pavois reference (pavois-content/{os_name}.yml). Do not edit by hand.\n\n"
            + "\n".join(ctrls), encoding="utf-8")
    print(f"{os_name}: {len(ref)} controls -> {out}  ({len(groups)} files)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
