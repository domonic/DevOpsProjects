#!/bin/bash
# setup-clusters.sh — discovers and configures EKS clusters for OpenLens
# Supports normal access and break-glass admin mode.

set -euo pipefail

DEVELOPER_ROLE_ARN="arn:aws:iam::644533755319:role/eks-developer-role"
BREAKGLASS_ROLE_ARN="arn:aws:iam::644533755319:role/eks-breakglass-admin"
TAG_KEY="developer-access"
TAG_VALUE="true"
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
MODE="normal"  # default mode

# ─── Parse arguments ──────────────────────────────────────────────────────────

usage() {
  echo "Usage: $0 [--breakglass]"
  echo ""
  echo "Options:"
  echo "  --breakglass    Configure ALL clusters with admin access (requires MFA)"
  echo "  --help          Show this help"
  echo ""
  echo "Default: configures only clusters tagged developer-access=true with"
  echo "         the standard developer role (View/Edit access)."
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --breakglass) MODE="breakglass"; shift ;;
    --help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# ─── Pre-checks ──────────────────────────────────────────────────────────────

echo "Verifying AWS credentials..."
if ! aws sts get-caller-identity --no-cli-pager > /dev/null 2>&1; then
  echo "ERROR: AWS credentials not configured or expired."
  exit 1
fi

if [ "$MODE" = "breakglass" ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  BREAK-GLASS MODE                                           ║"
  echo "║  This grants full ClusterAdmin on ALL clusters.             ║"
  echo "║  Use only during active incidents.                          ║"
  echo "║  This action is logged and triggers an alert to on-call.    ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  read -p "Confirm break-glass access? [y/N]: " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi

  ROLE_ARN="$BREAKGLASS_ROLE_ARN"

  # Verify MFA-gated assumption works
  echo "Verifying break-glass role assumption (requires MFA)..."
  if ! aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name breakglass-test \
    --query 'Credentials.AccessKeyId' --output text > /dev/null 2>&1; then
    echo "ERROR: Cannot assume break-glass role."
    echo "Ensure your principal is tagged breakglass=authorized and MFA is active."
    exit 1
  fi
else
  ROLE_ARN="$DEVELOPER_ROLE_ARN"

  echo "Verifying developer role assumption..."
  if ! aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name dev-test \
    --query 'Credentials.AccessKeyId' --output text > /dev/null 2>&1; then
    echo "ERROR: Cannot assume $ROLE_ARN"
    exit 1
  fi
fi

# ─── Discover and configure clusters ─────────────────────────────────────────

TOTAL=0
CONFIGURED=0

echo ""
if [ "$MODE" = "breakglass" ]; then
  echo "Configuring ALL clusters with ClusterAdmin access..."
else
  echo "Scanning for clusters tagged $TAG_KEY=$TAG_VALUE..."
fi
echo ""

for region in "${REGIONS[@]}"; do
  clusters=$(aws eks list-clusters --region "$region" --no-cli-pager \
    --query 'clusters' --output text 2>/dev/null)

  if [ -z "$clusters" ]; then
    continue
  fi

  for cluster in $clusters; do
    TOTAL=$((TOTAL + 1))

    # In normal mode, filter by tag. In break-glass mode, include everything.
    if [ "$MODE" = "normal" ]; then
      tags=$(aws eks describe-cluster --name "$cluster" --region "$region" \
        --no-cli-pager --query 'cluster.tags' --output json 2>/dev/null)

      access_tag=$(echo "$tags" | python3 -c "
import sys, json
tags = json.load(sys.stdin) or {}
print(tags.get('$TAG_KEY', ''))" 2>/dev/null)

      if [ "$access_tag" != "$TAG_VALUE" ]; then
        continue
      fi
    fi

    alias="${region}/${cluster}"
    aws eks update-kubeconfig \
      --name "$cluster" \
      --region "$region" \
      --role-arn "$ROLE_ARN" \
      --alias "$alias" \
      --no-cli-pager > /dev/null 2>&1

    echo "  ✓ $alias"
    CONFIGURED=$((CONFIGURED + 1))
  done
done

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────────────"
echo "Mode:       $MODE"
echo "Role:       $ROLE_ARN"
echo "Scanned:    $TOTAL clusters across ${#REGIONS[@]} regions"
echo "Configured: $CONFIGURED clusters"
echo "─────────────────────────────────────────"

if [ "$MODE" = "breakglass" ]; then
  echo ""
  echo "⚠  Break-glass session is limited to 1 hour."
  echo "⚠  On-call has been notified of this access."
  echo "⚠  Re-run without --breakglass when incident is resolved."
fi

echo ""
echo "Lens — clusters are ready."
