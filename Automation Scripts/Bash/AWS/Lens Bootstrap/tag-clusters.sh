#!/bin/bash
# tag-clusters.sh — Tag EKS clusters for developer access via OpenLens
#
# Tags clusters with:
#   developer-access=true          (enables discovery by the developer role)
#   developer-access-level=<level> (controls View vs Edit access)
#
# Supported access levels:
#   view  → AmazonEKSViewPolicy (read-only)
#   edit  → AmazonEKSEditPolicy (read-write on workloads)
#   admin → AmazonEKSClusterAdminPolicy (full cluster admin)

set -euo pipefail

REGIONS=("us-east-1" "us-west-2" "eu-west-1")

# ─── Defaults ─────────────────────────────────────────────────────────────────

ACCESS_LEVEL="view"
MODE=""
CLUSTER_NAMES=()
REGION_FILTER=""
DRY_RUN=false

# ─── Access level mapping ─────────────────────────────────────────────────────

resolve_policy() {
  case "$1" in
    view)  echo "AmazonEKSViewPolicy" ;;
    edit)  echo "AmazonEKSEditPolicy" ;;
    admin) echo "AmazonEKSClusterAdminPolicy" ;;
    *)     echo "ERROR: Invalid access level '$1'. Use: view, edit, admin" >&2; exit 1 ;;
  esac
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  tag       Tag clusters for developer access
  untag     Remove developer access tags from clusters
  list      Show current tagging status of all clusters

Options:
  --clusters <name,...>   Comma-separated cluster names (default: all in region)
  --region <region>       Limit to a single region (default: all configured regions)
  --level <view|edit|admin>  Access level to grant (default: view)
  --dry-run              Show what would be done without making changes

Examples:
  # Tag all clusters in us-east-1 with edit access
  $0 tag --region us-east-1 --level edit

  # Tag specific clusters with view access
  $0 tag --clusters my-app-prod,my-app-staging --level view

  # Remove developer access from a cluster
  $0 untag --clusters my-app-prod

  # See current state across all regions
  $0 list

  # Preview changes without applying
  $0 tag --level edit --dry-run
EOF
  exit 0
}

# ─── Parse arguments ──────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  usage
fi

MODE="$1"; shift

case "$MODE" in
  tag|untag|list) ;;
  --help|-h) usage ;;
  *) echo "Unknown command: $MODE"; usage ;;
esac

while [[ $# -gt 0 ]]; do
  case $1 in
    --clusters)
      IFS=',' read -ra CLUSTER_NAMES <<< "$2"; shift 2 ;;
    --region)
      REGION_FILTER="$2"; shift 2 ;;
    --level)
      ACCESS_LEVEL="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    --help|-h)
      usage ;;
    *)
      echo "Unknown option: $1"; usage ;;
  esac
done

# ─── Pre-checks ──────────────────────────────────────────────────────────────

echo "Verifying AWS credentials..."
if ! aws sts get-caller-identity --no-cli-pager > /dev/null 2>&1; then
  echo "ERROR: AWS credentials not configured or expired."
  exit 1
fi

POLICY_NAME=$(resolve_policy "$ACCESS_LEVEL")

# Narrow regions if --region was specified
if [ -n "$REGION_FILTER" ]; then
  REGIONS=("$REGION_FILTER")
fi

# ─── Discover clusters ────────────────────────────────────────────────────────

discover_clusters() {
  local region="$1"
  local clusters

  clusters=$(aws eks list-clusters --region "$region" --no-cli-pager \
    --query 'clusters' --output text 2>/dev/null)

  if [ -z "$clusters" ]; then
    return
  fi

  for cluster in $clusters; do
    # If specific clusters were requested, filter
    if [ ${#CLUSTER_NAMES[@]} -gt 0 ]; then
      local match=false
      for name in "${CLUSTER_NAMES[@]}"; do
        if [ "$cluster" = "$name" ]; then
          match=true
          break
        fi
      done
      if [ "$match" = false ]; then
        continue
      fi
    fi
    echo "$region/$cluster"
  done
}

# ─── Tag command ──────────────────────────────────────────────────────────────

do_tag() {
  echo ""
  echo "Tagging clusters for developer access"
  echo "  Access level: $ACCESS_LEVEL → $POLICY_NAME"
  if [ "$DRY_RUN" = true ]; then
    echo "  Mode: DRY RUN (no changes will be made)"
  fi
  echo ""

  local count=0

  for region in "${REGIONS[@]}"; do
    local targets
    targets=$(discover_clusters "$region")

    if [ -z "$targets" ]; then
      continue
    fi

    for target in $targets; do
      local cluster="${target#*/}"
      local r="${target%%/*}"

      if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would tag $r/$cluster:"
        echo "            developer-access=true"
        echo "            developer-access-level=$POLICY_NAME"
      else
        aws eks tag-resource \
          --resource-arn "$(aws eks describe-cluster --name "$cluster" --region "$r" \
            --no-cli-pager --query 'cluster.arn' --output text)" \
          --tags "developer-access=true,developer-access-level=$POLICY_NAME" \
          --region "$r" --no-cli-pager

        echo "  ✓ $r/$cluster → $ACCESS_LEVEL ($POLICY_NAME)"
      fi

      count=$((count + 1))
    done
  done

  echo ""
  echo "─────────────────────────────────────────"
  if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete. $count cluster(s) would be tagged."
  else
    echo "Done. $count cluster(s) tagged."
  fi
  echo "─────────────────────────────────────────"
}

# ─── Untag command ────────────────────────────────────────────────────────────

do_untag() {
  echo ""
  echo "Removing developer access tags from clusters"
  if [ "$DRY_RUN" = true ]; then
    echo "  Mode: DRY RUN (no changes will be made)"
  fi
  echo ""

  local count=0

  for region in "${REGIONS[@]}"; do
    local targets
    targets=$(discover_clusters "$region")

    if [ -z "$targets" ]; then
      continue
    fi

    for target in $targets; do
      local cluster="${target#*/}"
      local r="${target%%/*}"

      if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would untag $r/$cluster:"
        echo "            Remove: developer-access, developer-access-level"
      else
        aws eks untag-resource \
          --resource-arn "$(aws eks describe-cluster --name "$cluster" --region "$r" \
            --no-cli-pager --query 'cluster.arn' --output text)" \
          --tag-keys "developer-access" "developer-access-level" \
          --region "$r" --no-cli-pager

        echo "  ✓ $r/$cluster — tags removed"
      fi

      count=$((count + 1))
    done
  done

  echo ""
  echo "─────────────────────────────────────────"
  if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete. $count cluster(s) would be untagged."
  else
    echo "Done. $count cluster(s) untagged."
    echo ""
    echo "Note: Run 'terraform apply' to reconcile access entries."
  fi
  echo "─────────────────────────────────────────"
}

# ─── List command ─────────────────────────────────────────────────────────────

do_list() {
  echo ""
  echo "EKS Cluster Developer Access Status"
  echo "═══════════════════════════════════════════════════════════════"
  printf "%-12s %-30s %-10s %-30s\n" "REGION" "CLUSTER" "ACCESS" "LEVEL"
  echo "───────────────────────────────────────────────────────────────"

  for region in "${REGIONS[@]}"; do
    clusters=$(aws eks list-clusters --region "$region" --no-cli-pager \
      --query 'clusters' --output text 2>/dev/null)

    if [ -z "$clusters" ]; then
      continue
    fi

    for cluster in $clusters; do
      tags=$(aws eks describe-cluster --name "$cluster" --region "$region" \
        --no-cli-pager --query 'cluster.tags' --output json 2>/dev/null)

      access_tag=$(echo "$tags" | python3 -c "
import sys, json
tags = json.load(sys.stdin) or {}
print(tags.get('developer-access', '-'))" 2>/dev/null)

      level_tag=$(echo "$tags" | python3 -c "
import sys, json
tags = json.load(sys.stdin) or {}
print(tags.get('developer-access-level', '-'))" 2>/dev/null)

      # Color coding
      if [ "$access_tag" = "true" ]; then
        status="✓ enabled"
      else
        status="✗ disabled"
      fi

      printf "%-12s %-30s %-10s %-30s\n" "$region" "$cluster" "$status" "$level_tag"
    done
  done

  echo "═══════════════════════════════════════════════════════════════"
  echo ""
}

# ─── Execute ──────────────────────────────────────────────────────────────────

case "$MODE" in
  tag)   do_tag ;;
  untag) do_untag ;;
  list)  do_list ;;
esac
