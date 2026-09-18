#!/usr/bin/env bash
# Give GitHub Actions the ability to publish the site, with no long-lived AWS key anywhere.
#
# Two objects are created, both additive and both removable:
#   - the GitHub OIDC provider (account-wide, but it grants nothing on its own: it only lets roles
#     trust GitHub-issued tokens, and no existing role trusts it)
#   - a role scoped to this repo AND two refs, allowed to write ONLY the pavois bucket and
#     invalidate ONLY the pavois distribution. It cannot see the account's other sites.
set -euo pipefail
ACC=276757567417
REPO=stephrobert/pavois
BUCKET=pavois-dev-site
DIST=EYT0MDPPDEF19
ROLE=pavois-site-deploy
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

PROVIDER_ARN="arn:aws:iam::${ACC}:oidc-provider/token.actions.githubusercontent.com"

if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  echo "==> creating the GitHub OIDC provider"
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd \
    >/dev/null
else
  echo "==> OIDC provider already present, left alone"
fi

# Two refs, and the second one is a WIDENING of the trust boundary, so it is stated rather than
# slipped in. Until now only `refs/heads/main` could assume this role, a ref that nothing but a
# reviewed merge can move. A release runs on a TAG, so release.yml's deploy job presents
# `repo:<repo>:ref:refs/tags/vX.Y.Z` and is refused by an exact match on main. Without this the
# only way a release reaches the site is a human dispatching the deploy, which is the defect
# (#329) that the call in release.yml removes.
#
# What it costs: anybody who can push a `v*` tag to this repository can now assume a role that
# writes the site bucket and invalidates the distribution. On a repository where main is protected
# and tags are not, a tag is the weaker door of the two. If that becomes the wrong trade, the fix
# is a tag ruleset (or a `v[0-9]*` pattern here), NOT a long-lived AWS key: the no-stored-secret
# property is the one worth keeping.
#
# StringLike, with a list, because a list under StringEquals would still require an exact match and
# `refs/tags/v*` needs the wildcard. The main entry carries no wildcard, so it stays exact.
cat > "$W/trust.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "${PROVIDER_ARN}" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": [
          "repo:${REPO}:ref:refs/heads/main",
          "repo:${REPO}:ref:refs/tags/v*"
        ]
      }
    }
  }]
}
JSON

cat > "$W/policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublishSiteObjects",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    },
    {
      "Sid": "ListSiteBucketForSync",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::${BUCKET}"
    },
    {
      "Sid": "InvalidateThisDistributionOnly",
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"],
      "Resource": "arn:aws:cloudfront::${ACC}:distribution/${DIST}"
    }
  ]
}
JSON

if aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  echo "==> role exists, updating its trust policy"
  aws iam update-assume-role-policy --role-name "$ROLE" --policy-document "file://$W/trust.json"
else
  echo "==> creating role $ROLE"
  aws iam create-role --role-name "$ROLE" \
    --description "GitHub Actions publishes the pavois.dev site. Scoped to this repo, main and v* tags." \
    --assume-role-policy-document "file://$W/trust.json" >/dev/null
fi

aws iam put-role-policy --role-name "$ROLE" --policy-name site-publish \
  --policy-document "file://$W/policy.json"

echo
echo "role arn: arn:aws:iam::${ACC}:role/${ROLE}"
