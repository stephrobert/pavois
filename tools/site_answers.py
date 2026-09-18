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
   so the assertion is on the DNS rather than on the connection: every address two public resolvers
   hand out, A and AAAA, must be a CloudFront address, checked against the ranges AWS publishes.

Usage: python3 tools/site_answers.py      (exit 1 on anything wrong, and it says which)
"""

from __future__ import annotations

import ipaddress
import json
import shutil
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

# The security headers, and the reason they are asserted rather than trusted: two of them stopped
# being served and nobody noticed for a fortnight. #210 quotes a live capture with
# `Permissions-Policy` and an HSTS `preload` token; the site served neither until this was written.
# CloudFront's SecurityHeadersConfig has no Permissions-Policy field, so it vanished the moment the
# console policy became a versioned script, silently, which is the whole failure mode.
#
# Each entry is (header, what must appear in its value). A substring, not the whole value: the CSP
# is long and evolves, and pinning it whole would make this a copy of the policy rather than a
# check that the policy is applied.
HEADERS = [
    ("strict-transport-security", "max-age=63072000"),
    ("strict-transport-security", "preload"),
    ("permissions-policy", "geolocation=()"),
    ("content-security-policy", "default-src 'self'"),
    ("content-security-policy", "frame-ancestors 'self'"),
    ("x-content-type-options", "nosniff"),
    ("referrer-policy", "strict-origin-when-cross-origin"),
]

# A real DNS query, and the resolver that answers is whichever one CAN answer.
#
# Two attempts got this wrong in opposite directions, and both are worth keeping written down.
#
#   socket.getaddrinfo answers for THIS HOST: on a machine with no global IPv6 address it filters
#   the AAAA family out entirely, so the runner reported "no AAAA record" for a name that has
#   eight. It was measuring the runner's network stack, not the zone.
#
#   Asking 1.1.1.1 and 8.8.8.8 directly then returned NOTHING for every query: a GitHub runner does
#   not get to send DNS to an arbitrary public resolver. It was measuring the runner's egress.
#
# So the sources are tried in order and the first one that answers is the one used: the system
# resolver, which is what a visitor on this machine actually uses, and the public ones as a
# fallback for a host whose own resolver is broken or blocked. `dig` rather than the libc path,
# because dig asks for the record type it was told to ask for, whatever this host can connect to.
SOURCES = [None, "1.1.1.1", "8.8.8.8"]  # None: whatever /etc/resolv.conf points at
AWS_RANGES = "https://ip-ranges.amazonaws.com/ip-ranges.json"

fails: list[str] = []
warns: list[str] = []


def bad(msg: str) -> None:
    print(f"  FAIL {msg}")
    fails.append(msg)


def warn(msg: str) -> None:
    """Said out loud, never fatal: a deploy gate that reds on the environment gets switched off."""
    print(f"  warn {msg}")
    warns.append(msg)


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


def headers_of(url: str) -> dict[str, str]:
    """Response headers, lowercased, from the page a reader actually gets."""
    try:
        out = subprocess.run(
            ["curl", "-sSI", "--max-time", "30", "-L", url],
            capture_output=True,
            text=True,
            timeout=60,
        ).stdout
    except subprocess.SubprocessError as e:
        bad(f"could not read the headers of {url} ({e})")
        return {}
    got: dict[str, str] = {}
    for line in out.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            got[k.strip().lower()] = v.strip()
    return got


def have_dig() -> bool:
    return shutil.which("dig") is not None


def dig(name: str, rr: str, resolver: str | None) -> list[str]:
    """The addresses that resolver hands out for that name, and nothing else.

    `dig +short` also prints CNAME targets and, on failure, its own diagnostics, so only lines that
    parse as an address are kept: a check that counts a hostname as an address reports success for
    a name that resolves to nothing.
    """
    cmd = ["dig", "+short", "+time=5", "+tries=2", rr, name]
    if resolver:
        cmd.append(f"@{resolver}")
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
    except subprocess.SubprocessError:
        return []
    addrs = []
    for line in out.split():
        try:
            addrs.append(str(ipaddress.ip_address(line)))
        except ValueError:
            continue
    return sorted(addrs)


def resolve(name: str, rr: str) -> tuple[list[str], str]:
    """The first source that answers wins, and the answer says which one it was."""
    for src in SOURCES:
        got = dig(name, rr, src)
        if got:
            return got, src or "system resolver"
    return [], "no resolver answered"


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

    print("\n--- the security headers a hardening project is judged on")
    got = headers_of(f"{WWW}/en/")
    for header, wanted in HEADERS:
        value = got.get(header, "")
        if wanted in value:
            print(f"  {header}: {wanted}")
        else:
            bad(f"{header} does not carry {wanted!r} (got {value or 'nothing'!r})")

    print("\n--- every address, A and AAAA, belongs to CloudFront")
    if not have_dig():
        bad("dig is not installed, so the address check cannot run (apt: bind9-dnsutils)")
    else:
        nets = cloudfront_networks()
        for name in NAMES:
            for rr in ("A", "AAAA"):
                got, src = resolve(name, rr)
                print(f"  {name} {rr} ({src}): {' '.join(got) if got else 'NOTHING'}")
                if not got and rr == "A":
                    bad(f"{name} has no A record: the site is unreachable")
                elif not got:
                    # NOT fatal, and the reason is the two wrong turns above: a host can be unable
                    # to SEE a AAAA that exists. The incident this check is for was an address that
                    # was WRONG, not one that was missing, and a wrong address is caught below
                    # whichever source answers.
                    warn(f"{name}: no AAAA from any source (a host filtering IPv6 looks the same)")
                for addr in got:
                    if nets and not any(ipaddress.ip_address(addr) in n for n in nets):
                        bad(f"{name} {rr} is {addr}, which is not a CloudFront address")

    print()
    if fails:
        print(f"{len(fails)} problem(s): the deployed site does not answer the way it must")
        return 1
    # The closing line says what this run actually established, which is not always the same
    # sentence. The first green run printed "both names answer on both address families" under two
    # warnings saying no AAAA could be seen at all: a summary that claims more than the run checked
    # is how a green gate stops meaning anything.
    if warns:
        print("the front door redirects to /en/ and every address SEEN is CloudFront, but the")
        print(f"IPv6 side was not observable from here ({len(warns)} warning(s) above)")
    else:
        print("both names answer on both address families, and the front door redirects to /en/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
