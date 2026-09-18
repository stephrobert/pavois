#!/usr/bin/env python3
"""Provision the test fleet as Incus VIRTUAL MACHINES, so a scan means something.

Pavois demands a real scan before a rule change merges, and until now the only published harness
provisioned on a Proxmox host. This provisions on Incus, on the machine you are already sitting at:
a laptop, no hypervisor, no root SSH to a server.

**Virtual machines, never containers.** `incus launch --vm` is not a preference here, it is the
difference between a verdict and a lie. 259 of the 789 controls cannot be answered by a container:
70 sysctl, 62 kernel-build (KSPP), 38 mounts, 23 kernel modules, 35 auditd, 18 kernel cmdline, 11
filesystem, plus grub and MAC. A container shares the host kernel, so those controls do not skip:
they measure YOUR machine. Run from a hardened workstation, a container scan hands back PASSes that
say nothing about the target, which is the worst failure a compliance tool can have, because it is
green. `pavois scan` now refuses this outright; --allow-container overrides it, and
the kernel controls then describe YOUR machine, which is almost never what you want.

  mise run vm -- up debian12        # create + wait for SSH, then print the scan command
  PAVOIS_SUDO_PASSWORD=... mise run vm -- up debian12 --sudo-password   # value from the env
  mise run vm -- list
  mise run vm -- ip debian12
  mise run vm -- down debian12

`--sudo-password` is worth using before you trust a hardening run: the cloud default is NOPASSWD,
real hosts are not, and the sudo path is where `harden apply` has broken before.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

# Incus image aliases, /cloud variants (they carry cloud-init, which is how sshd gets enabled:
# an Incus VM is a full OS and exposes nothing by default).
IMAGES = {
    # key = the pavois profile (ls profiles/linux/), value = the Incus image alias.
    # RHEL itself is not distributable, so its profiles are exercised on AlmaLinux, which is what
    # `pavois scan` auto-detects to rhel<major> anyway (profileForOS in go/cmd/scan.go).
    "debian12": "images:debian/12/cloud",
    "debian13": "images:debian/13/cloud",
    "ubuntu2204": "images:ubuntu/jammy/cloud",
    "ubuntu2404": "images:ubuntu/noble/cloud",
    "ubuntu2604": "images:ubuntu/26.04/cloud",
    "rhel8": "images:almalinux/8/cloud",
    "rhel9": "images:almalinux/9/cloud",
    "rhel10": "images:almalinux/10/cloud",
    "fedora": "images:fedora/43/cloud",
}

# Every image above lives on the `images:` remote, which Incus configures out of the box. The
# ubuntu LTS releases are aliased by CODENAME there (jammy, noble), not by version number, which
# is why a search for "ubuntu/24.04" comes back empty and Canonical's own simplestreams endpoint
# looks like the answer: it is not, it serves public-cloud image ids, and Incus finds nothing in it.

# Which pavois profile each OS is scanned with (`pavois scan` auto-detects; this is for the hint
# printed at the end, and it mirrors profileForOS in go/cmd/scan.go).
# The profile is the key itself, so no second map to keep in sync.

USER = "pavois"
GREEN, RED, DIM, OFF = "\033[32m", "\033[31m", "\033[2m", "\033[0m"
if not sys.stdout.isatty():
    GREEN = RED = DIM = OFF = ""


def incus(*args: str, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(["incus", *args], text=True, capture_output=capture, check=False)


def name_of(os_key: str) -> str:
    return f"pavois-{os_key}"


def cloud_init(pubkey: str, sudo_password: str | None) -> str:
    """cloud-init that installs sshd and the pavois account. Nothing else is assumed."""
    sudo_line = (
        '    sudo: "ALL=(ALL) ALL"' if sudo_password else '    sudo: "ALL=(ALL) NOPASSWD:ALL"'
    )
    login_lines = ""  # cloud-init lines that set a login password, when one is asked for
    if sudo_password:
        # plain_text_passwd is lab-only and never leaves this machine; it exists so the realistic
        # password-sudo path can be exercised, which is where harden apply has broken before.
        login_lines = f"    lock_passwd: false\n    plain_text_passwd: {sudo_password}\n"
    return (
        "#cloud-config\n"
        "package_update: true\n"
        "packages:\n"
        "  - openssh-server\n"
        "users:\n"
        f"  - name: {USER}\n"
        "    groups: [sudo, wheel]\n"
        f"{sudo_line}\n"
        "    shell: /bin/bash\n"
        f"{login_lines}"
        "    ssh_authorized_keys:\n"
        f"      - {pubkey}\n"
        "ssh_pwauth: false\n"
        "runcmd:\n"
        "  - systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd\n"
    )


def managed_networks() -> list[str]:
    """Incus-managed networks, i.e. the ones a VM can actually be attached to."""
    out = incus("network", "list", "--format", "json", capture=True).stdout
    try:
        nets = json.loads(out or "[]")
    except json.JSONDecodeError:
        return []
    return [n["name"] for n in nets if n.get("managed")]


def has_nic(name: str) -> bool:
    """True when the instance ended up with at least one network device."""
    out = incus("config", "show", name, "--expanded", capture=True).stdout
    return "nictype:" in out or "network:" in out


def ipv4(name: str) -> str | None:
    out = incus("list", name, "--format", "json", capture=True).stdout
    try:
        data = json.loads(out or "[]")
    except json.JSONDecodeError:
        return None
    if not data:
        return None
    for iface, net in ((data[0].get("state") or {}).get("network") or {}).items():
        if iface == "lo":
            continue
        for addr in net.get("addresses", []):
            if addr["family"] == "inet" and addr["scope"] == "global":
                return addr["address"]
    return None


def wait_for_ssh(name: str, timeout: int = 300) -> str | None:
    """Wait for an address, then for sshd. cloud-init installs it, so both take a while."""
    deadline = time.time() + timeout
    ip = None
    while time.time() < deadline:
        ip = ip or ipv4(name)
        if ip:
            probe = subprocess.run(
                [
                    "ssh",
                    # -F /dev/null: this machine's ~/.ssh/config carries a `Host *` ProxyJump,
                    # which breaks a direct connection to a lab address, and the ssh CLI honours it
                    # and the connection dies at the banner exchange. pavois already passes
                    # --ssh-config-file /dev/null to cinc for the same reason; without it here the
                    # probe waits out its whole timeout and reports a perfectly healthy VM as dead.
                    "-F",
                    "/dev/null",
                    "-o",
                    "BatchMode=yes",
                    "-o",
                    "StrictHostKeyChecking=no",
                    "-o",
                    "UserKnownHostsFile=/dev/null",
                    "-o",
                    "ConnectTimeout=4",
                    f"{USER}@{ip}",
                    "true",
                ],
                capture_output=True,
                check=False,
            )
            if probe.returncode == 0:
                return ip
        time.sleep(5)
        where = f" ({ip})" if ip else ""
        print(f"  {DIM}waiting for {name}{where}…{OFF}", end="\r", file=sys.stderr)
    return None


def gib(spec: str) -> float:
    """Parse an Incus memory spec (4GiB, 2048MiB, 8GB) into GiB. 0.0 when unparseable."""
    m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*([KMGT]i?B?)?", spec.strip(), re.I)
    if not m:
        return 0.0
    n = float(m.group(1))
    unit = (m.group(2) or "B").upper().rstrip("B").rstrip("I")
    return n * {"": 1 / 2**30, "K": 1 / 2**20, "M": 1 / 1024, "G": 1.0, "T": 1024.0}.get(unit, 0.0)


def available_gib() -> float:
    """MemAvailable, which is what can actually be handed out without swapping."""
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) / 2**20
    except OSError:
        pass
    return 0.0


def check_memory(requested: str, headroom: float = 6.0) -> str | None:
    """Refuse a VM that would eat the machine it is running on.

    A test VM is a guest on somebody's working laptop, and it competes with their editor, their
    browser and whatever else is already running. Starting a 12GiB guest next to eight existing
    ones once pushed this very machine into swap and cost its owner their session, so the tool
    checks before it launches rather than apologising afterwards. `headroom` is what is left FOR
    the host, not for the guest.
    """
    want = gib(requested)
    have = available_gib()
    if want <= 0 or have <= 0:
        return None  # cannot tell: never refuse on a guess
    if want + headroom > have:
        return (
            f"vm: {requested} would leave {have - want:.1f}GiB for everything else on this machine "
            f"({have:.1f}GiB available now).\n"
            f"    Free memory, stop other guests (`incus list`, `virsh list`), or ask for less:\n"
            f"    --memory {max(2, int(have - headroom))}GiB"
        )
    return None


def sudo_password_of(args) -> str | None:
    """The password, from the ENVIRONMENT, never from argv.

    A value passed on the command line is refused rather than used: accepting it "just this once"
    is what put `--sudo-password pavois` into `ps` output on a machine every user can read. The
    harness did it (golden_path.sh), and then so did a maintainer debugging that very defect, which
    is how you learn a rule nobody can follow is not a rule.
    """
    if args.sudo_password:
        print(
            "vm: refusing a password given on the command line (ps is world readable).\n"
            "    export PAVOIS_SUDO_PASSWORD instead, then pass --sudo-password with no value.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if args.sudo_password is None:
        return None
    pw = os.environ.get("PAVOIS_SUDO_PASSWORD", "")
    if not pw:
        print(
            "vm: --sudo-password given but PAVOIS_SUDO_PASSWORD is empty.\n"
            "    export it (from a file, a password manager, anything but argv) and retry.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    return pw


def cmd_up(args: argparse.Namespace) -> int:
    sudo_pw = sudo_password_of(args)
    if args.os not in IMAGES:
        print(f"vm: unknown OS {args.os!r} (known: {', '.join(sorted(IMAGES))})", file=sys.stderr)
        return 2
    pub = Path(args.key).expanduser()
    if not pub.exists():
        print(
            f"vm: no public key at {pub}: pass --key, or make one with ssh-keygen",
            file=sys.stderr,
        )
        return 2

    problem = check_memory(args.memory)
    if problem:
        print(problem, file=sys.stderr)
        return 2

    name = name_of(args.os)
    if ipv4(name) or incus("info", name, capture=True).returncode == 0:
        print(f"vm: {name} already exists (`mise run vm -- down {args.os}` first)", file=sys.stderr)
        return 1

    # A default profile with no NIC is normal on a host that manages several networks, and
    # the symptom is silent: the VM boots, runs, and never gets an address. Refuse now.
    nets = managed_networks()
    if args.network not in nets:
        print(
            f"vm: no Incus-managed network called {args.network!r}. "
            f"Managed here: {', '.join(nets) or 'none'}.\n"
            f"    Pass --network <name>, or create one: incus network create {args.network}",
            file=sys.stderr,
        )
        return 2

    # An image alias may be overridden, and the reason is not convenience: the `images:` remote
    # stalled mid release once (11 KiB/s for a 300 MB VM image, no Incus operation registered, the
    # run wedged for 13 minutes on `incus init`), and a proof harness that cannot run because a
    # third-party mirror is slow proves nothing about the product. A locally cached image of the
    # same distribution answers the same question; the campaign's claim is about the CORPUS, so the
    # evidence records which image it ran on.
    #   PAVOIS_VM_IMAGE=feint/debian/12 mise run vm -- up debian12
    image = os.environ.get("PAVOIS_VM_IMAGE") or IMAGES[args.os]
    if image != IMAGES[args.os]:
        print(f"image overridden: {image} (default {IMAGES[args.os]})", file=sys.stderr)
    # A local alias (no `remote:` prefix) needs no remote at all, and the check below would ask
    # for one named after the alias itself.
    remote = image.split(":", 1)[0] if ":" in image else ""
    configured = subprocess.run(
        ["incus", "remote", "list", "--format", "csv"], capture_output=True, text=True, check=False
    ).stdout
    if remote and remote not in [
        line.split(",")[0].replace(" (current)", "") for line in configured.splitlines()
    ]:
        hint = f"incus remote add {remote} <url>"
        print(
            f"vm: {args.os} needs the {remote!r} image remote, which is not configured.\n"
            f"    Add it with:  {hint}",
            file=sys.stderr,
        )
        return 2

    print(f"vm: launching {name} as a VIRTUAL MACHINE ({image}, {args.cpu} vCPU, {args.memory})")
    # init + add the agent disk + start, rather than a single `launch`.
    #
    # Some VM images refuse to create without it: "This virtual machine image requires an
    # agent:config disk be added" (measured on images:almalinux/9/cloud, which is what the rhel9
    # profile is exercised on). The disk carries the incus-agent the guest installs at first boot;
    # debian's VM images bring their own, the EL ones do not. `launch` gives no opportunity to add
    # a device, and `-d agent,...` is refused because the device is not in the profile yet.
    rc = incus(
        "init",
        image,
        name,
        "--vm",
        "-c",
        f"limits.cpu={args.cpu}",
        "-c",
        f"limits.memory={args.memory}",
        "-d",
        f"root,size={args.disk}",
        # explicit: the default profile may carry no NIC at all, and the symptom is silent
        "-n",
        args.network,
        # Secure Boot OFF, because these VMs exist to run the KSPP kernel recipe and a kernel you
        # compiled yourself is not signed by a key shim trusts. Left on, the build succeeds, the
        # reboot never comes back, and the only trace is on the serial console:
        #     error: bad shim signature.
        #     error: you need to load the kernel first.
        #     Failed to boot both default and fallback entries.
        # This is a property of the test fleet, not advice: on a real host under Secure Boot a
        # custom kernel needs signing and a MOK enrolled, which the recipe deliberately does not do.
        "-c",
        "security.secureboot=false",
        "-c",
        f"cloud-init.user-data={cloud_init(pub.read_text().strip(), sudo_pw)}",
    ).returncode
    if rc == 0:
        # Harmless when the image already provides it; required when it does not.
        incus("config", "device", "add", name, "agent", "disk", "source=agent:config", capture=True)
        rc = incus("start", name).returncode
    if rc != 0:
        print(
            f"{RED}vm: launch failed.{OFF} A VM image is required. Do NOT fall back to a\n"
            "container: 259 of 789 controls would then measure this host, not the target.",
            file=sys.stderr,
        )
        return 1

    if not has_nic(name):
        print(
            f"{RED}vm: {name} launched with no network device.{OFF} "
            "It will never answer; delete it and retry with a valid --network.",
            file=sys.stderr,
        )
        return 1

    ip = wait_for_ssh(name)
    print(" " * 60, end="\r", file=sys.stderr)
    if not ip:
        print(
            f"{RED}vm: {name} never answered on SSH.{OFF} Watch it boot with:\n"
            f"    script -qec 'incus console {name}' /dev/null",
            file=sys.stderr,
        )
        return 1

    profile = f"linux/{args.os}"
    sudo_flag = "--sudo-prompt" if sudo_pw else "--sudo"
    print(f"{GREEN}vm: {name} is up at {ip}{OFF}\n")
    print("Scan it:")
    key = pub.with_suffix("")
    print(
        f"    bin/pavois scan {USER}@{ip} --profile {profile} {sudo_flag} --on-target --key {key}"
    )
    if sudo_pw:
        print(f"    {DIM}(PAVOIS_SUDO_PASSWORD is read by --sudo-prompt when set){OFF}")
    print(f"\nHarden it:\n    bin/pavois harden plan {USER}@{ip} {sudo_flag}")
    return 0


def cmd_down(args: argparse.Namespace) -> int:
    name = name_of(args.os)
    rc = incus("delete", name, "--force").returncode
    print(f"vm: {name} {'deleted' if rc == 0 else 'not deleted (does it exist?)'}")
    return rc


def cmd_list(_: argparse.Namespace) -> int:
    out = incus("list", "^pavois-", "--format", "json", capture=True).stdout
    try:
        data = json.loads(out or "[]")
    except json.JSONDecodeError:
        data = []
    if not data:
        print("vm: no pavois VM. Create one: mise run vm -- up debian12")
        return 0
    for inst in data:
        kind = inst.get("type", "?")
        bad = f"  {RED}<- NOT A VM: unusable as a scan target{OFF}"
        mark = "" if kind == "virtual-machine" else bad
        addr = ipv4(inst["name"]) or "-"
        status = inst.get("status", "?")
        print(f"  {inst['name']:<24} {status:<10} {addr:<16} {kind}{mark}")
    return 0


def cmd_ip(args: argparse.Namespace) -> int:
    ip = ipv4(name_of(args.os))
    if not ip:
        return 1
    print(ip)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Provision pavois test VMs on Incus (VMs, never containers)."
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    up = sub.add_parser("up", help="create a VM and wait for SSH")
    up.add_argument("os", help=f"one of: {', '.join(sorted(IMAGES))}")
    up.add_argument("--key", default="~/.ssh/id_ed25519.pub", help="public key to authorize")
    up.add_argument("--cpu", default="2")
    up.add_argument(
        "--network",
        default="incusbr0",
        help="Incus managed network to attach (the default profile may have none)",
    )
    up.add_argument("--memory", default="4GiB", help="4GiB is enough; a kernel build wants more")
    up.add_argument("--disk", default="20GiB", help="a KSPP kernel build needs ~20GiB on its own")
    # The VALUE is deliberately not accepted on the command line any more: argv is world readable
    # through `ps`, and this repository's own rule says the lab password never appears there. It
    # was violated by the harness itself (golden_path.sh passed it as an argument) and then by a
    # maintainer debugging that very defect, which is how a rule nobody can follow gets found.
    # The flag now takes no value and reads PAVOIS_SUDO_PASSWORD from the environment.
    up.add_argument(
        "--sudo-password",
        nargs="?",
        const="",
        default=None,
        help="give the account a sudo PASSWORD instead of NOPASSWD; the value comes from "
        "PAVOIS_SUDO_PASSWORD, never from argv (ps is world readable)",
    )
    up.set_defaults(func=cmd_up)

    down = sub.add_parser("down", help="delete a VM")
    down.add_argument("os")
    down.set_defaults(func=cmd_down)

    sub.add_parser("list", help="list the pavois VMs").set_defaults(func=cmd_list)

    ip = sub.add_parser("ip", help="print a VM's address")
    ip.add_argument("os")
    ip.set_defaults(func=cmd_ip)

    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
