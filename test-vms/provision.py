#!/usr/bin/env python3
"""Flotte de VM de test pavois via Incus (cloud-init + SSH).

Chaque VM est une vraie VM (--vm) avec sshd activé par cloud-init, pour que
pavois l'audite par `ssh://` comme un serveur réel.

  test-vms/provision.py up debian12
  test-vms/provision.py list
  test-vms/provision.py down debian12

pavois doit ignorer le ssh_config global de l'hôte : c'est déjà géré côté moteur
(`--ssh-config-file /dev/null`) pour ne pas hériter d'un ProxyJump parasite.
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

KEY = Path.home() / ".ssh/id_ed25519"
USER = "pavois"

# Image Incus (variante /cloud = cloud-init) par OS de test.
IMAGES = {
    "debian12":   "images:debian/12/cloud",
    "ubuntu2404": "images:ubuntu/24.04/cloud",
    "rocky9":     "images:rockylinux/9/cloud",
    "alma9":      "images:almalinux/9/cloud",
    "fedora40":   "images:fedora/40/cloud",
}


def name_of(osk):
    return f"pavois-{osk}"


def cloud_init():
    pub = (KEY.with_suffix(".pub")).read_text().strip()
    return f"""#cloud-config
package_update: true
packages:
  - openssh-server
users:
  - name: {USER}
    groups: [sudo, wheel]
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    ssh_authorized_keys:
      - {pub}
runcmd:
  - systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd
"""


def _incus(*args, capture=False):
    return subprocess.run(["incus", *args], text=True,
                          capture_output=capture, check=False)


def ipv4(name):
    out = _incus("list", name, "--format", "json", capture=True).stdout
    data = json.loads(out or "[]")
    if not data:
        return None
    for net in (data[0].get("state") or {}).get("network", {}).items():
        if net[0] == "lo":
            continue
        for a in net[1].get("addresses", []):
            if a["family"] == "inet" and a["scope"] == "global":
                return a["address"]
    return None


def _provision_exec(name):
    """Installe sshd + user pavois + clé via `incus exec` (sans cloud-init).

    Repli robuste pour les conteneurs système et les images sans cloud-init
    (ex. RHEL). OS-agnostique : détecte apt ou dnf. Un conteneur système Incus
    fait tourner un vrai systemd, donc sshd/systemctl/services sont audités
    réellement — contrairement à Docker.
    """
    pub = (KEY.with_suffix(".pub")).read_text().strip()
    script = f"""set -e
if command -v dnf >/dev/null; then dnf install -y -q openssh-server sudo >/dev/null 2>&1
elif command -v apt-get >/dev/null; then apt-get update -qq >/dev/null 2>&1; \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server sudo >/dev/null 2>&1; fi
id {USER} >/dev/null 2>&1 || useradd -m {USER}
getent group wheel >/dev/null && usermod -aG wheel {USER} || usermod -aG sudo {USER} || true
echo '{USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/{USER}
install -d -m 700 -o {USER} -g {USER} /home/{USER}/.ssh
echo '{pub}' > /home/{USER}/.ssh/authorized_keys
chown {USER}:{USER} /home/{USER}/.ssh/authorized_keys; chmod 600 /home/{USER}/.ssh/authorized_keys
ssh-keygen -A >/dev/null 2>&1 || true
systemctl enable --now sshd 2>/dev/null || systemctl enable --now ssh
"""
    _incus("exec", name, "--", "bash", "-c", script)


def up(osk, container=False):
    if osk not in IMAGES:
        sys.exit(f"OS inconnu: {osk} (dispo: {', '.join(IMAGES)})")
    name = name_of(osk)
    image = IMAGES[osk].replace("/cloud", "") if container else IMAGES[osk]
    kind = "conteneur système" if container else "VM"
    print(f"== création {name} ({image}, {kind}) ==")
    args = ["launch", image, name, "-c", "limits.cpu=2", "-c", "limits.memory=2GiB"]
    if not container:
        # VM : cloud-init installe sshd. (Repli si une image VM échoue : --container.)
        args += ["--vm", "-c", f"cloud-init.user-data={cloud_init()}"]
    if _incus(*args).returncode != 0:
        sys.exit("échec du lancement"
                 + ("" if container else " (image VM capricieuse ? réessaie avec --container)"))
    if container:
        print("== provisioning (sshd + user) via incus exec ==")
        _incus("exec", name, "--", "bash", "-c", "until systemctl is-system-running 2>/dev/null "
               "| grep -qE 'running|degraded'; do sleep 1; done")
        _provision_exec(name)
    else:
        print("== attente cloud-init (install sshd) ==")
        _incus("exec", name, "--", "cloud-init", "status", "--wait")
    ip = None
    for _ in range(40):
        ip = ipv4(name)
        if ip:
            break
        time.sleep(3)
    if not ip:
        sys.exit("pas d'IPv4 (agent/réseau ?)")
    print(f"\n{kind} prêt : {name}  ->  {ip}")
    print("Scanner avec pavois :")
    print(f"  bin/pavois scan {USER}@{ip} --key {KEY} --sudo --profile <profil>")


def down(osk):
    name = name_of(osk)
    _incus("delete", name, "--force")
    print(f"{name} supprimée")


def lst(_osk=None):
    _incus("list", "pavois-")


def main():
    p = argparse.ArgumentParser(description="Flotte de VM de test pavois (Incus).")
    sub = p.add_subparsers(dest="cmd", required=True)
    sp_up = sub.add_parser("up")
    sp_up.add_argument("os", choices=list(IMAGES))
    sp_up.add_argument("--container", action="store_true",
                       help="conteneur système (vrai systemd) au lieu d'une VM ; "
                            "repli quand l'image VM Incus échoue (ex. RHEL)")
    sp_dn = sub.add_parser("down")
    sp_dn.add_argument("os", choices=list(IMAGES))
    sub.add_parser("list")
    args = p.parse_args()
    if args.cmd == "list":
        lst()
    elif args.cmd == "up":
        up(args.os, container=args.container)
    else:
        down(args.os)


if __name__ == "__main__":
    main()
