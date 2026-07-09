#!/usr/bin/env bash
# One-time AWS-side setup for .github/workflows/aws-ops.yml.
# Creates the GitHub OIDC identity provider and the IAM role the workflow assumes.
# Requires local AWS credentials with IAM write access (e.g. the ofekpc user).
# Idempotent-ish: safe to re-run; create calls that hit "already exists" are tolerated.
set -uo pipefail

ACCOUNT_ID=191106064063
REPO="ofekm5/zero-rtt-tcp"
ROLE_NAME="zero-rtt-demo-github-actions"  # name predates the repo rename (zero-rtt-demo -> zero-rtt-tcp); left as-is to match the already-deployed role
REGION="eu-central-1"

TRUST=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
      "StringLike": {"token.actions.githubusercontent.com:sub": "repo:${REPO}:*"}
    }
  }]
}
EOF
)

POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AssumeCdkBootstrapRoles",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/cdk-*"
    },
    {
      "Sid": "ExperimentOrchestration",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ssm:GetCommandInvocation",
        "cloudformation:DescribeStacks"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SsmRunShellScript",
      "Effect": "Allow",
      "Action": "ssm:SendCommand",
      "Resource": [
        "arn:aws:ssm:${REGION}::document/AWS-RunShellScript",
        "arn:aws:ec2:${REGION}:${ACCOUNT_ID}:instance/*"
      ]
    }
  ]
}
EOF
)

echo "[1/4] OIDC provider..."
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 1c58a3a8518e8759bf075b76b750d4f2df264fcd \
  2>/dev/null || echo "  (already exists — ok)"

echo "[2/4] IAM role $ROLE_NAME..."
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document "$TRUST" \
  --description "GitHub Actions OIDC role for $REPO (CDK deploy + SSM experiments)" \
  --max-session-duration 14400 \
  --query Role.Arn --output text 2>/dev/null || echo "  (already exists — ok)"

echo "[3/4] Inline policy..."
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name zero-rtt-demo-ops \
  --policy-document "$POLICY"

echo "[4/4] GitHub repo variable AWS_ROLE_ARN..."
gh variable set AWS_ROLE_ARN --repo "$REPO" \
  --body "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "Done. Role: arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
