#!/usr/bin/env python3
"""What the deployed site must answer, asserted from outside AWS.

The previous version of this check was one line, `https://www.pavois.dev/` must be 200, and it
failed for the best possible reason: the front door became a 301 at the edge (the root REDIRECTS to
/en/ instead of serving a meta-refresh page), so demanding 200 on it was demanding the old bug back.
A check that has to be weakened when the product improves was measuring the wrong thing.

Three families, one incident each.

1. Every URL a reader can type ends at 200, redirects followed. The original failure mode was a
   green upload serving 403, when the bucket policy and the origin access control disagreed.

2. The APEX, on a PATH. #292: `pavois.dev/en/installation/` was answered by the registrar's
   redirection service, which discards the path by construction, so every deep link landed on the
   home page. The root alone cannot see it: the root is the one path a path-discarding redirect
   gets right, which is why this was reported by a reader and not by CI.

3. The ADDRESSES, both families. The apex was right over IPv4 and, for a resolver still holding the
   old delegation, pointed at the registrar over IPv6. Browsers prefer IPv6, so those visitors were
   sent to the wrong host while every IPv4 check stayed green. The runner has no IPv6 connectivity,
   so the assertion is on the DNS rather than the connection: every address the name resolves to,
   A and AAAA, must be a CloudFront address, checked against the ranges AWS publishes.

Usage: python3 tools/site_answers.py      (exit 1 on anything wrong, and it says which)
"""

from __future__ import annotations

import ipaddress
import json
import socket
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

APEX = "https://pavois.dev"
WWW = "https://www.pavois.dev"

# Followed to the end, each must land on a page AND STILL BE THE PAGE THAT WAS ASKED FOR. The second
# half is the whole of #292: the registrar's redirection service answered every apex URL with the
# home page, so a status-only check reads 200 and the reader reads the wrong page. The roots are the
# exception by design: they redirect to /en/.
ENDS_AT = [
    (f"{WWW}/", "/en/"),
    (f"{APEX}/", "/en/"),
    (f"{WWW}/en/rules/", "/en/rules/"),
    (f"{APEX}/en/installation/", "/en/installation/"),
    (f"{APEX}/fr/installation/", "/fr/installation/"),
]

# The front door is a redirect, not a page. Astro's static Astro.redirect() emits a meta-refresh
# served 200, with a noindex, on the canonical address of the project.
REDIRECTS_TO_EN = [f"{APEX}/", f"{WWW}/"]

NAMES = ["pavois.dev", "www.pavois.dev"]
AWS_RANGES = "https://ip-ranges.amazonaws.com/ip-ranges.json"

fails: list[str] = []


def bad(msg: str) -> None:
    print(f"  FAIL {msg}")
    fails.append(msg)


def curl(url: str, follow: bool) -> tuple[str, str]:
    """(status, where it ended). curl rather than urllib: it is what the operator will re-run.

    Following, the second value is the URL actually reached; not following, it is the Location.
    """
    fmt = "%{http_code} %{url_effective}" if follow else "%{http_code} %{redirect_url}"
    args = ["curl", "-sS", "--max-time", "30", "-o", "/dev/null", "-w", fmt]
    if follow:
        args.append("-L")
    try:
        out = subprocess.run([*args, url], capture_output=True, text=True, timeout=60).stdout
    except subprocess.SubprocessError as e:
        return "000", f"({e})"
    parts = out.split(maxsplit=1)
    return (parts[0] if parts else "000"), (parts[1].strip() if len(parts) > 1 else "")


def cloudfront_networks() -> list:
    """The CloudFront prefixes, from the list AWS publishes: no hardcoded range to go stale."""
    last = ""
    for _ in range(3):
        try:
            # AWS_RANGES is a literal https URL: there is no scheme to smuggle here.
            with urllib.request.urlopen(AWS_RANGES, timeout=30) as r:  # nosec B310
                data = json.load(r)
            nets = [
                ipaddress.ip_network(p["ip_prefix"])
                for p in data.get("prefixes", [])
                if p.get("service") == "CLOUDFRONT"
            ]
            nets += [
                ipaddress.ip_network(p["ipv6_prefix"])
                for p in data.get("ipv6_prefixes", [])
                if p.get("service") == "CLOUDFRONT"
            ]
            return nets
        except (urllib.error.URLError, TimeoutError, ValueError, KeyError) as e:
            last = str(e)
    bad(f"could not read the AWS ranges to check the addresses against ({last})")
    return []


def main() -> int:
    print("--- every entry point ends at 200, on the page that was asked for")
    for url, want in ENDS_AT:
        code, ended = curl(url, follow=True)
        print(f"  {url} -> {code}  {ended}")
        if code != "200":
            bad(f"{url} answered {code}, not 200")
        elif urllib.parse.urlsplit(ended).path != want:
            bad(f"{url} ended on {ended}, not on {want}: the path was discarded on the way")

    print("\n--- the front door redirects, it does not serve a page")
    for url in REDIRECTS_TO_EN:
        code, loc = curl(url, follow=False)
        print(f"  {url} -> {code} {loc}")
        if code not in ("301", "302", "308"):
            bad(f"{url} answered {code}: the root must redirect, not serve a page")
        elif not loc.endswith("/en/"):
            bad(f"{url} redirects to {loc or 'nothing'}, not to /en/")

    print("\n--- every address, A and AAAA, belongs to CloudFront")
    nets = cloudfront_networks()
    for name in NAMES:
        try:
            got = sorted({ai[4][0] for ai in socket.getaddrinfo(name, 443)})
        except socket.gaierror as e:
            bad(f"{name} does not resolve ({e})")
            continue
        v4 = [a for a in got if ":" not in a]
        v6 = [a for a in got if ":" in a]
        print(f"  {name}: {len(v4)} A, {len(v6)} AAAA")
        if not v4:
            bad(f"{name} has no A record")
        if not v6:
            # Not cosmetic: a browser on an IPv6-only network cannot reach a name without one, and
            # the CloudFront distribution serves both.
            bad(f"{name} has no AAAA record: IPv6 visitors cannot reach it")
        for addr in got:
            ip = ipaddress.ip_address(addr)
            if nets and not any(ip in n for n in nets):
                bad(f"{name} resolves to {addr}, which is not a CloudFront address")

    print()
    if fails:
        print(f"{len(fails)} problem(s): the deployed site does not answer the way it must")
        return 1
    print("both names answer on both address families, and the front door redirects to /en/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
