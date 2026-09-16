#!/usr/bin/env bash
# Turn on CloudFront access logs for www.pavois.dev.
#
# Why this exists: when Search Console said "generic HTTP error" on the sitemap, there was nothing
# to look at. Every probe from here answered 200 with valid XML, which proves what OUR requests get,
# not what Googlebot got. An access log is the only record of what the edge actually served to a
# given user-agent at a given time, and it is the difference between diagnosing and guessing.
#
#   tools/aws/site-access-logs.sh            # show the current state
#   tools/aws/site-access-logs.sh --apply    # create the bucket and enable logging
#
# Standard logs, not real-time: delivery takes minutes to a few hours, which is fine for answering
# "did Googlebot fetch the sitemap, and what did it get". Real-time logs mean Kinesis, and a bill.
#
# The bucket keeps 90 days. Access logs grow without limit and nobody ever reads one older than a
# quarter; an unbounded log bucket is a cost that compounds quietly.
set -uo pipefail

DIST_ID=EYT0MDPPDEF19
BUCKET=pavois-dev-logs
REGION=us-east-1
PREFIX=cloudfront/

state() {
  echo "=== distribution logging ==="
  aws cloudfront get-distribution-config --id "$DIST_ID" --query 'DistributionConfig.Logging' --output json | sed 's/^/  /'
  echo "=== bucket ==="
  if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "  $BUCKET exists"
    aws s3 ls "s3://$BUCKET/$PREFIX" 2>/dev/null | tail -3 | sed 's/^/  /' || echo "  (no object yet)"
  else
    echo "  $BUCKET does not exist"
  fi
}

if [ "${1:-}" != "--apply" ]; then
  state
  echo
  echo "run with --apply to enable"
  exit 0
fi

if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "=== creating $BUCKET ==="
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null || exit 1

  # CloudFront's standard log delivery writes with an ACL, so the bucket must accept ACLs. This is
  # the ONE place where the modern "disable ACLs entirely" default has to be relaxed, and it is
  # relaxed no further than that: public access stays fully blocked below.
  aws s3api put-bucket-ownership-controls --bucket "$BUCKET" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerPreferred}]' || exit 1

  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true' || exit 1

  aws s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' || exit 1

  aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
    --lifecycle-configuration \
    '{"Rules":[{"ID":"expire-90d","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":90}}]}' || exit 1

  echo "  created, private, encrypted, 90-day retention"
fi

echo "=== enabling logging on the distribution ==="
TMP=$(mktemp -d)
aws cloudfront get-distribution-config --id "$DIST_ID" > "$TMP/dist.json" || exit 1
ETAG=$(python3 -c "import json;print(json.load(open('$TMP/dist.json'))['ETag'])")

python3 - "$TMP/dist.json" "$TMP/config.json" "$BUCKET" "$PREFIX" <<'PY'
import json, sys
src, dst, bucket, prefix = sys.argv[1:5]
cfg = json.load(open(src))["DistributionConfig"]
cfg["Logging"] = {
    "Enabled": True,
    "IncludeCookies": False,   # no cookie is set by this site; logging them would be pure liability
    "Bucket": f"{bucket}.s3.amazonaws.com",
    "Prefix": prefix,
}
json.dump(cfg, open(dst, "w"))
PY

aws cloudfront update-distribution --id "$DIST_ID" --if-match "$ETAG" \
  --distribution-config "file://$TMP/config.json" \
  --query 'Distribution.DistributionConfig.Logging' --output json | sed 's/^/  /' || exit 1
rm -rf "$TMP"

echo
echo "Logs land in s3://$BUCKET/$PREFIX, gzipped, one file per batch. Delivery takes minutes to a"
echo "few hours, so the first file is not immediate. Read them with tools/aws/site-log-query.sh."
