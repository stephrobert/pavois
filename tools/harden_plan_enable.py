#!/usr/bin/env python3
"""Turn a state-aware pavois plan into a full-hardening plan, deterministically.

Encodes the enable policy the operator would otherwise apply by hand:
  - every `status: gap` -> apply: true
  - EXCEPT `danger:` items, which stay off unless whitelisted as boot-safe:
      * grub-password        (pavois appends --unrestricted -> boot-safe)
      * firewall-default-deny (gets ssh_allow_from so SSH is never cut)
    kmod-loading-disabled / mount-var-noexec stay OFF (brick / breaks apt).
  - SSH lock-out guards: ssh_allow_users on misc-sshd-limit-user-access,
    ssh_allow_from on firewall-default-deny (so a re-apply never drops access).
  - baseline package installs -> apply: true

This is the automation half of "the result must be produced by pavois": no
per-run hand-editing of the YAML plan.

Usage: harden_plan_enable.py <plan.yml> --ssh-user pavois [--ssh-from CIDR ...]
"""

import argparse

import yaml

# danger items that ARE safe to auto-apply, with why
SAFE_DANGERS = {"grub-password", "firewall-default-deny"}
# danger items that must NEVER auto-apply (brick / breaks package manager)
KEEP_OFF = {"kmod-loading-disabled", "mount-var-noexec"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("plan")
    ap.add_argument("--ssh-user", default="pavois")
    ap.add_argument("--ssh-from", action="append", default=[])
    a = ap.parse_args()

    with open(a.plan) as f:
        d = yaml.safe_load(f)
    rules = d.get("rules", {})
    enabled = acked = 0
    for rid, r in rules.items():
        if not isinstance(r, dict):
            continue
        if r.get("status") != "gap":
            continue
        # install-time / kernel-build / manual: no apply can close this gap (it takes a partition
        # recipe, a kernel rebuild, a human). Enabling it anyway makes every convergence pass
        # "apply" it, achieve nothing, and never reach a fixpoint.
        if r.get("class"):
            continue
        if rid in KEEP_OFF:
            continue
        if "danger" in r and rid not in SAFE_DANGERS:
            continue
        r["apply"] = True
        enabled += 1
        if "danger" in r:
            r["acknowledged"] = True
            acked += 1

    # lock-out guards
    s = rules.get("misc-sshd-limit-user-access")
    if isinstance(s, dict) and s.get("apply"):
        s["ssh_allow_users"] = [a.ssh_user]
    fw = rules.get("firewall-default-deny")
    if isinstance(fw, dict) and fw.get("apply") and a.ssh_from:
        fw["ssh_allow_from"] = list(a.ssh_from)

    for pkg in d.get("baseline_packages", []):
        pkg["apply"] = True

    with open(a.plan, "w") as f:
        yaml.safe_dump(d, f, default_flow_style=False, sort_keys=False, width=1000)
    print(
        f"enabled {enabled} gaps ({acked} safe-dangers acked), "
        f"baseline pkgs on, ssh_allow_users={a.ssh_user}, ssh_from={a.ssh_from or 'any'}"
    )


if __name__ == "__main__":
    main()
