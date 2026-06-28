#!/usr/bin/env python3
"""DEV seeder (one-time): bake the remediation knowledge INTO the pavois reference
so it lives as DATA, never as code. For every control in
docs/reference/pavois-content/<os>.yml it sets:

  - `remediation`     : resource-oriented spec (compiles to NATIVE Chef resources,
                        never bash) for the derivable domains; null otherwise
                        (pending — declarative template content to be sourced from NixOS).
  - `requires_package`: the baseline prerequisite whose absence makes the control
                        skip (n/a); installing it once (batched) flips it to a gap.

The runtime (the Go `pavois harden` command / the plan generator) then only READS
these fields. Knowledge in the reference, not in the code.

Usage: tools/seed_remediation.py [<os> ...]   (default: all OS references)
"""
import re
import sys
import yaml
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "docs" / "reference" / "pavois-content"


def remediation_for(cid, e):
    """Resource-oriented remediation (-> native Chef resources, no bash)."""
    check = " ".join(e.get("check", []))
    # auditd rule checks (`auditctl -l … -k <key>`) are all satisfied by deploying the
    # pavois audit ruleset (docs/reference/audit.rules) — one shared file drop-in.
    if "auditctl -l" in check:
        return {"resource": "audit_ruleset", "reboot_required": True}
    m = re.fullmatch(r"pkg-(.+)-(removed|installed)", cid)
    if m:
        return {"resource": "package", "name": m.group(1),
                "action": "remove" if m.group(2) == "removed" else "install"}
    m = re.fullmatch(r"service-(.+)-(disabled|enabled|masked)", cid)
    if m:
        act = {"disabled": ["disable", "stop"], "enabled": ["enable", "start"],
               "masked": ["mask"]}[m.group(2)]
        return {"resource": "service", "name": m.group(1), "action": act}
    m = re.fullmatch(r"kmod-(.+)-disabled", cid)
    if m:
        # blacklisting an already-loaded module only takes effect after reboot
        return {"resource": "kernel_module", "name": m.group(1).replace("-", "_"),
                "action": "blacklist", "reboot_required": True}
    # sshd: effective directive via `sshd -T` -> a verified, reloading drop-in
    if "sshd -T" in check:
        sm = re.search(r"match\(/\^(\w+)\\s\+([\w.,@:+-]+)\$/", check)
        if sm:
            return {"resource": "sshd_setting", "directive": sm.group(1), "value": sm.group(2),
                    "verify": "sshd -t -f %{path}", "notify": {"service": "ssh", "action": "reload"}}
    km = re.search(r"kernel_parameter\('([^']+)'\)", check)
    # capture the FULL quoted value (ranges like '32768 65535'), else a bare token
    vm = re.search(r"should (?:cmp|eq) '([^']*)'", check) or re.search(r"should (?:cmp|eq) (\S+)", check)
    if km and vm:
        return {"resource": "sysctl", "key": km.group(1), "value": vm.group(1)}
    # sysctl checked via a shell command: [ "$(sysctl -n <key>)" = "<value>" ]
    cm = re.search(r'sysctl -n ([\w.]+)[^=]*=\s*"([^"]+)"', check)
    if cm:
        return {"resource": "sysctl", "key": cm.group(1), "value": cm.group(2)}
    # sudoers Defaults option -> a verified /etc/sudoers.d/ drop-in (visudo -c, no bash).
    # the option comes from the cid (robust) — e.g. sudo-noexec, sudo-use-pty.
    sm = re.match(r"sudo-([\w-]+)$", cid)
    if sm and "/etc/sudoers" in check and "Defaults" in check:
        opt = sm.group(1).replace("-", "_")
        # most options are boolean flags (`Defaults noexec`); a few REQUIRE a value or
        # visudo rejects them (`Defaults umask` is invalid -> needs `umask=0027`).
        body = {"umask": "Defaults umask=0027\nDefaults umask_override\n"}.get(
            opt, f"Defaults {opt}\n")
        return {"resource": "file", "path": f"/etc/sudoers.d/99-pavois-{opt}",
                "content": body, "verify": "visudo -cf %{path}"}
    fm = re.search(r"\bfile\('([^']+)'\)", check)
    if fm:
        r = {"resource": "file", "path": fm.group(1)}
        mo = re.search(r"its\('mode'\) \{ should cmp '?([0-7]+)'?", check)
        ow = re.search(r"its\('owner'\) \{ should eq '([^']+)'", check)
        gr = re.search(r"its\('group'\) \{ should eq '([^']+)'", check)
        if mo:
            r["mode"] = mo.group(1)
        if ow:
            r["owner"] = ow.group(1)
        if gr:
            r["group"] = gr.group(1)
        if len(r) > 2:
            return r
    # key=value threshold config with a .conf.d/ drop-in (pwquality, faillock) — the
    # compliant value is the threshold boundary; written to a pavois drop-in file.
    km = re.search(r"(\w+)\[\[:space:\]\]\*=", check)
    dm = re.search(r"(/[\w/.-]+\.conf\.d)", check)
    tm = re.search(r"-(le|ge) (-?\d+)", check)
    if km and dm and tm:
        return {"resource": "keyval", "file": dm.group(1) + "/99-pavois.conf",
                "key": km.group(1), "value": tm.group(2)}
    return None


# baseline prerequisite: the package whose absence makes the control skip (n/a)
BASELINE_PKG = [
    (re.compile(r"^audit|/etc/audit|auditd"), "auditd"),
    (re.compile(r"chrony"), "chrony"),
    (re.compile(r"/etc/at\.(allow|deny)"), "at"),
    (re.compile(r"/etc/cron"), "cron"),
    (re.compile(r"\baide\b"), "aide"),
]


def requires_package_for(cid, e):
    hay = cid + " " + " ".join(e.get("check", []))
    for rx, pkg in BASELINE_PKG:
        if rx.search(hay):
            return pkg
    return None


def file_attrs(rules):
    """path -> {mode,owner,group} learned from the file perm/owner controls, so a
    `should exist` control can be remediated by CREATING the file with the right attrs."""
    attrs = {}
    for e in rules.values():
        check = " ".join(e.get("check", []))
        fm = re.search(r"\bfile\('([^']+)'\)", check)
        if not fm:
            continue
        a = attrs.setdefault(fm.group(1), {})
        mo = re.search(r"its\('mode'\) \{ should cmp '?([0-7]+)'?", check)
        ow = re.search(r"its\('owner'\) \{ should eq '([^']+)'", check)
        gr = re.search(r"its\('group'\) \{ should eq '([^']+)'", check)
        if mo:
            a["mode"] = mo.group(1)
        if ow:
            a["owner"] = ow.group(1)
        if gr:
            a["group"] = gr.group(1)
    return attrs


def create_file_remediation(e, attrs):
    """A `should exist` control on a required file -> create it (native file resource)."""
    check = " ".join(e.get("check", []))
    fm = re.search(r"\bfile\('([^']+)'\)", check)
    if not (fm and "should exist" in check):
        return None
    r = {"resource": "file", "path": fm.group(1), "content": "",
         "mode": "0600", "owner": "root", "group": "root"}
    r.update(attrs.get(fm.group(1), {}))  # prefer attrs learned from sibling controls
    return r


def seed(os_name):
    p = CONTENT / f"{os_name}.yml"
    lines = p.read_text().splitlines()
    header = "\n".join(l for l in lines[:3] if l.startswith("#")) + "\n"
    doc = yaml.safe_load(p.read_text())
    attrs = file_attrs(doc["rules"])
    derived = pending = 0
    for cid, e in doc["rules"].items():
        if (e.get("remediation") or {}).get("resource") == "choose":
            continue  # "<group>-present": its choose remediation is owned by resolve_exclusivity
        rem = remediation_for(cid, e)
        if rem is None:
            rem = create_file_remediation(e, attrs)
        e["remediation"] = rem
        if rem:
            derived += 1
        else:
            pending += 1
        rp = requires_package_for(cid, e)
        if rp:
            e["requires_package"] = rp
        elif "requires_package" in e:
            del e["requires_package"]
    p.write_text(header + yaml.safe_dump(doc, sort_keys=True, allow_unicode=True,
                                         default_flow_style=False, width=400), encoding="utf-8")
    print(f"{os_name}: remediation derived {derived}, pending {pending}")


def main(args):
    oses = args or [p.stem for p in sorted(CONTENT.glob("*.yml"))]
    for os in oses:
        seed(os)


if __name__ == "__main__":
    main(sys.argv[1:])
