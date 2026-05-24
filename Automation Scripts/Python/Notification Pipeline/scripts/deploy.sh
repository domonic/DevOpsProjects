#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# AWS Infrastructure Lifecycle Alerts — Deployment Script
# =============================================================================
#
# Usage:
#   export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
#   ./scripts/deploy.sh [dev|prod]
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Terraform >= 1.5 installed
#   - SLACK_WEBHOOK_URL environment variable set
# =============================================================================

ENV="${1:-dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"

echo "=============================================="
echo "  AWS Infrastructure Lifecycle Alerts"
echo "  Environment: $ENV"
echo "=============================================="
echo ""

# Validate prerequisites
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform >= 1.5"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install and configure AWS CLI"
    exit 1
fi

if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    echo "❌ SLACK_WEBHOOK_URL environment variable is not set"
    echo "   Export it before running: export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...'"
    exit 1
fi

# Verify AWS credentials
echo "🔍 Verifying AWS credentials..."
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
if [ -z "$AWS_ACCOUNT" ]; then
    echo "❌ AWS credentials not configured or expired"
    exit 1
fi
echo "   Account: $AWS_ACCOUNT"
echo ""

# Initialize Terraform
echo "📦 Initializing Terraform..."
cd "$TERRAFORM_DIR"
terraform init -upgrade
echo ""

# Plan
echo "📋 Planning changes..."
terraform plan \
    -var-file="environments/${ENV}.tfvars" \
    -var="slack_webhook_url=${SLACK_WEBHOOK_URL}" \
    -out=tfplan
echo ""

# Confirm
read -p "🚀 Apply these changes? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Deployment cancelled"
    rm -f tfplan
    exit 0
fi

# Apply
echo ""
echo "⚡ Applying changes..."
terraform apply tfplan
rm -f tfplan
echo ""

echo "=============================================="
echo "  ✅ Deployment Complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Test with: make test-events"
echo "  2. Check your Slack channel: #$(terraform output -raw slack_channel 2>/dev/null || echo 'infra-alerts')"
echo "  3. (Optional) Deploy K8s Event Exporter: make deploy-k8s"
echo ""
