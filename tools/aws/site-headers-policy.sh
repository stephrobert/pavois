#!/usr/bin/env bash
# The CloudFront response-headers policy for www.pavois.dev, in the repository rather than only in
# the console. A security policy that exists nowhere but a web console cannot be reviewed, cannot
# be diffed, and cannot be explained six months later.
#
# Idempotent: reads the current policy, rewrites it with the config below, bumps the ETag.
#
#   tools/aws/site-headers-policy.sh            # show the current policy and the diff
#   tools/aws/site-headers-policy.sh --apply    # write it
#
# WHAT CHANGED AND WHY, 2026-09-16
#
# The policy shipped `frame-ancestors 'none'` and `X-Frame-Options: DENY`, which forbid embedding
# by ANYONE, the site itself included. That broke the sample report and sample campaign on
# /<lang>/sample-report/: both are iframes of a page served from this very origin, and both
# rendered as an empty box. `'self'` keeps every other site from framing us, which is the attack
# this header exists to stop, and lets our own page embed our own report.
#
# It also shipped `font-src 'self'` and `style-src 'self' 'unsafe-inline'` while every page loads
# Google Fonts. The browser blocked them silently and fell back to system fonts: no error anyone
# would notice, a site that did not look like itself. The two Google Fonts origins are now
# declared, and nothing else is.
#
# Everything else is deliberately tight and stays that way:
#   default-src 'self'      nothing loads from anywhere else unless named below
#   object-src 'none'       no Flash/Java/embed surface
#   base-uri 'self'         a injected <base> cannot re-point every relative URL
#   form-action 'self'      a form cannot be made to post elsewhere
#   upgrade-insecure-requests
#
# The Plausible origin is named in script-src (the tracker) and connect-src (where it POSTs each
# pageview). A tracker blocked by CSP fails silently and reports nothing, which is exactly how the
# Google Fonts went missing: no error, no data, and no way to notice without looking.
#
# 'unsafe-inline' for scripts is a real weakness and is NOT fixed here: the anti-FOUC script, the
# nav drawer and the glossary tooltips are inline in Base.astro. Removing it needs either hashes
# or a nonce, which needs the build to emit them. Tracked, not pretended away.
#
# WHAT CHANGED AND WHY, 2026-09-18
#
# Two headers the site once served had quietly stopped being served, and an audit of the open
# issues found it, not a person looking at the site: `Permissions-Policy` and the `preload` token
# on HSTS. #210 quotes both from a live capture. CloudFront's SecurityHeadersConfig has no field
# for Permissions-Policy, which is why it went missing the moment this policy became the source of
# truth: it has to go in CustomHeadersConfig, and it now does. The features are denied outright
# because a documentation site needs none of them, and a hardening project is judged on its own
# headers.
#
# `tools/site_answers.py` now asserts these headers after every deploy, so the next disappearance
# is a red build rather than a discovery months later.
set -uo pipefail

POLICY_ID=079bcc13-132a-4c31-af51-55a293f1a789
POLICY_NAME=pavois-dev-security-headers

CSP="default-src 'self'; \
script-src 'self' 'unsafe-inline' https://analytics.stephrobert.tech; \
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; \
img-src 'self' data:; \
font-src 'self' https://fonts.gstatic.com; \
connect-src 'self' https://analytics.stephrobert.tech; \
object-src 'none'; \
base-uri 'self'; \
form-action 'self'; \
frame-ancestors 'self'; \
upgrade-insecure-requests"

current() {
  aws cloudfront get-response-headers-policy --id "$POLICY_ID" \
    --query 'ResponseHeadersPolicy.ResponseHeadersPolicyConfig.{Frame:SecurityHeadersConfig.FrameOptions.FrameOption,CSP:SecurityHeadersConfig.ContentSecurityPolicy.ContentSecurityPolicy,HSTSPreload:SecurityHeadersConfig.StrictTransportSecurity.Preload,Custom:CustomHeadersConfig.Items[].Header}' \
    --output json
}

if [ "${1:-}" != "--apply" ]; then
  echo "=== current ==="
  current
  echo
  echo "=== wanted ==="
  printf '{\n    "Frame": "SAMEORIGIN",\n    "CSP": "%s",\n    "HSTSPreload": true,\n    "Custom": [\n        "Permissions-Policy"\n    ]\n}\n' "$CSP"
  echo
  echo "run with --apply to write it"
  exit 0
fi

ETAG=$(aws cloudfront get-response-headers-policy --id "$POLICY_ID" --query 'ETag' --output text) || exit 1

CONFIG=$(cat <<JSON
{
  "Name": "$POLICY_NAME",
  "Comment": "Security headers for www.pavois.dev. Source of truth: tools/aws/site-headers-policy.sh",
  "SecurityHeadersConfig": {
    "ContentSecurityPolicy": { "Override": true, "ContentSecurityPolicy": "$CSP" },
    "ContentTypeOptions": { "Override": true },
    "FrameOptions": { "Override": true, "FrameOption": "SAMEORIGIN" },
    "ReferrerPolicy": { "Override": true, "ReferrerPolicy": "strict-origin-when-cross-origin" },
    "StrictTransportSecurity": {
      "Override": true,
      "AccessControlMaxAgeSec": 63072000,
      "IncludeSubdomains": true,
      "Preload": true
    },
    "XSSProtection": { "Override": true, "Protection": true, "ModeBlock": true }
  },
  "CustomHeadersConfig": {
    "Quantity": 1,
    "Items": [
      {
        "Header": "Permissions-Policy",
        "Value": "accelerometer=(), autoplay=(), camera=(), display-capture=(), encrypted-media=(), fullscreen=(self), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), payment=(), picture-in-picture=(), publickey-credentials-get=(), screen-wake-lock=(), sync-xhr=(), usb=(), xr-spatial-tracking=()",
        "Override": true
      }
    ]
  }
}
JSON
)

echo "$CONFIG" > /tmp/pavois-headers-policy.json
aws cloudfront update-response-headers-policy \
  --id "$POLICY_ID" \
  --if-match "$ETAG" \
  --response-headers-policy-config file:///tmp/pavois-headers-policy.json \
  --query 'ResponseHeadersPolicy.Id' --output text || exit 1
rm -f /tmp/pavois-headers-policy.json

echo "applied. CloudFront propagates in a minute or two; the headers are served from the edge, so"
echo "no cache invalidation is needed for them."
