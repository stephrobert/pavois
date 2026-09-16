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
from pathlib import Path

import yaml

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
        return "{" + ", ".join(_rb(k) + " => " + _rb(v) for k, v in s.items()) + "}"
    if isinstance(s, (list, tuple)):  # merged rules keep distinct per-norm values as an array
        return "[" + ", ".join(_rb(x) for x in s) + "]"
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'") + "'"


# Shell keywords that cannot be the first word of a command under --sudo.
#
# The transport prefixes `sudo ` to the command STRING, which the remote shell reads as
# `sudo cmd1; cmd2`. Measured on a live debian12 target:
#
#     id -u                    -> 0      (root)
#     echo "$(id -u)"          -> 1000   (NOT root)
#     for s in ufw ...; do ... -> ""     (`sudo for` is not a command: no output at all)
#
# A control whose command starts with a keyword therefore produces an EMPTY stdout, and its matcher
# reports a verdict on something it never measured. That is how firewall-present and
# firewall-default-deny claimed a HIGH deviation on a host whose nftables input chain was already
# `policy drop`. The engine's own --shell option does not fix it; that was tested.
#
# Wrapping the script as an argument of `sh -c` makes the first word a real binary, so
# `sudo sh -c '...'` runs the WHOLE line as root, keywords and substitutions included. Single
# quotes matter: with double quotes the remote shell expands $(...) before sudo runs, which moves
# the bug instead of removing it.
_SHELL_KEYWORDS = ("if", "for", "while", "until", "case", "test", "[")
# Ruby concatenates ADJACENT string literals, so `command('a''b')` is one string. A pattern
# matching a single literal silently skips those, and misc-postfix-anti-vrfy (which starts with
# `if`) went unwrapped and unreported because of exactly that. Match everything up to the
# closing `) do`, then strip the literal quoting.
_COMMAND_RE = re.compile(r"command\((\s*'(?:[^'\\]|\\.)*'(?:\s*'(?:[^'\\]|\\.)*')*)\)")


# A leading `NAME=value`: `sudo v=$(...)` hands sudo an environment assignment with no command,
# so nothing runs and stdout is empty, exactly like a leading keyword. This is the family that
# broke the twelve pwquality controls, the three umask ones and faillock: one cause, not eighteen.
_ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def _needs_shell_wrap(script):
    stripped = script.strip()
    if not stripped:
        return False
    first = stripped.split(None, 1)[0]
    return first in _SHELL_KEYWORDS or bool(_ASSIGNMENT_RE.match(first))


# Same defect, third syntax. These commands use Ruby DOUBLE quotes because they interpolate the
# per-standard value (`#{m}`), so the single-quote pattern above never sees them. They are the
# nastiest of the three: `sudo v=$(...)` leaves $v unset, the test takes its failure branch, and
# the command prints a confident "ko" instead of nothing. An empty stdout is detectable at runtime;
# a wrong answer is not.
#
# Escaping, carefully: inside a Ruby double-quoted literal, a POSIX-escaped single quote ('\'')
# must be written '\\''. The #{...} interpolation is left untouched: it is Ruby's, not the shell's.
_DQ_COMMAND_RE = re.compile(r'command\("((?:[^"\\]|\\.)*)"\)')


def _wrap_shell_dq(line):
    def repl(m):
        script = m.group(1)
        first = script.strip().split(None, 1)[0] if script.strip() else ""
        if not (first in _SHELL_KEYWORDS or _ASSIGNMENT_RE.match(first)):
            return m.group(0)
        # `'` in the Ruby literal is a literal quote for the shell: POSIX-escape it.
        escaped = script.replace("'", "'\\\\''")
        return "command(\"sh -c '" + escaped + "'\")"

    return _DQ_COMMAND_RE.sub(repl, line)


def _wrap_shell(line):
    """Rewrite command('<script>') as command("sh -c '<script>'") when the script starts with a
    shell keyword. Any other command is returned untouched."""

    def repl(m):
        # Join the adjacent literals into the single string Ruby would build.
        parts = re.findall(r"'((?:[^'\\]|\\.)*)'", m.group(1))
        script = "".join(parts).replace("\\'", "'").replace("\\\\", "\\")
        if not _needs_shell_wrap(script):
            return m.group(0)
        shell_arg = "sh -c '" + script.replace("'", "'\\''") + "'"
        return "command(" + _rb(shell_arg) + ")"

    return _COMMAND_RE.sub(repl, line)


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
    if e.get("danger"):
        out.append(f"  tag danger: {_rb(e['danger'])}")
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
    if e.get("remediation_class"):  # the scoring class comes from the RULE, never from Go
        out.append(f"  tag remediation_class: {_rb(e['remediation_class'])}")
    if e.get("ssg"):
        out.append(f"  tag ssg: {_rb(e['ssg'])}")
    # Mutual exclusivity ("one of"): a per-tech member is N/A when ANOTHER option in its
    # group already satisfies the requirement: `only_if` skips the control (-> n/a) unless
    # this tech is actually needed. The group's "is any active?" check comes from
    # exclusivity.yml. E.g. with rsyslog running, service-syslogng-enabled is N/A, not a gap.
    grp = e.get("exclusive_group")
    if grp and grp in EXCL:
        out.append(f"  tag exclusive_group: {_rb(grp)}")
        # Build the guard from the group's option services using the InSpec `service`
        # resource (reliable: no shell/PATH dependency): skip (-> n/a) if ANY option is
        # already running, since the "one of" requirement is then met by another tech.
        svcs = [o.get("service") for o in EXCL[grp].get("options", {}).values() if o.get("service")]
        cond = " || ".join(f"service({_rb(s)}).running?" for s in svcs) or "false"
        out.append(
            f"  only_if({_rb('n/a: another option in the ' + grp + ' group is active')}) "
            + "{ not ("
            + cond
            + ") }"
        )
    out += ["  " + _wrap_shell_dq(_wrap_shell(line)) for line in e.get("check", [])]
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
            f"# Rendered from pavois reference (pavois-content/{os_name}.yml). "
            "Do not edit by hand.\n\n" + "\n".join(ctrls),
            encoding="utf-8",
        )
    # Accepted risks -> an InSpec waiver file next to the controls. A control carrying a `waiver:`
    # justification is one we deliberately do NOT enforce because enforcing it would break the host
    # (e.g. noexec on /var kills apt) or because the check itself is defective. `run: false` makes
    # cinc SKIP it, so it stops counting as a failure while the justification stays in the report:
    # an auditable exception, the way OpenSCAP/CIS handle waivers.
    waived = {
        cid: {"run": False, "justification": ref[cid]["waiver"]}
        for cid in sorted(ref)
        if ref[cid].get("waiver")
    }
    wfile = out.parent / "waivers.yml"
    if waived:
        wfile.write_text(
            "# Accepted risks (generated: do not edit by hand). Each control here is\n"
            "# NOT enforced; the justification is what an auditor reads.\n"
            "# Source: the `waiver:` field in docs/reference/rules.yml.\n"
            + yaml.safe_dump(waived, sort_keys=True, allow_unicode=True, width=100),
            encoding="utf-8",
        )
    elif wfile.exists():
        wfile.unlink()
    # A profile without inspec.yml is NOT runnable: cinc refuses the directory ("doesn't
    # look like a supported profile structure"), and a scan that dies there can ship back
    # a stale report. Fail loudly here instead.
    if not (out.parent / "inspec.yml").exists():
        sys.exit(f"{os_name}: missing {out.parent}/inspec.yml: the profile would not be runnable")
    print(f"{os_name}: {len(ref)} controls -> {out}  ({len(groups)} files, {len(waived)} waived)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
