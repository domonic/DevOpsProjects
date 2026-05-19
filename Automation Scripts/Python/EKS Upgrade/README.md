# EKS Cluster Upgrade Script

Automates Amazon EKS cluster upgrades (control plane + data plane) with zero downtime. Supports managed node groups, self-managed node groups, AL2 to AL2023 AMI migrations, and custom AMI pipelines.

## Overview

The script upgrades one minor Kubernetes version at a time (e.g., 1.33 → 1.34). For multi-version jumps, run the script repeatedly. It handles the full lifecycle: pre-flight validation, control plane upgrade, add-on updates, and data plane rolling replacements.

## Usage

```bash
python3 upgrade.py <cluster-name> <region> [custom-ami-id]
```

| Argument | Default | Description |
|----------|---------|-------------|
| `cluster-name` | `my-cluster` | Name of the EKS cluster |
| `region` | `eu-west-2` | AWS region |
| `custom-ami-id` | None | Optional explicit AMI ID for self-managed nodes |

### Examples

```bash
# Upgrade a cluster in us-east-1
python3 upgrade.py production-cluster us-east-1

# Provide a custom AMI for self-managed nodes
python3 upgrade.py production-cluster us-east-1 ami-0abc123def456

# Run with defaults (my-cluster in eu-west-2)
python3 upgrade.py
```

## Workflow

The script follows a strict sequential process. Each step must complete before the next begins.

```
┌─────────────────────────────────────────────────────────────────┐
│  0. PRE-FLIGHT CHECKS                                           │
│  • Validate target version is supported in the region           │
│  • Ensure all node groups match current cluster version         │
│  • Ensure at least one node group has nodes (for add-ons)       │
│  • Migrate AL2 node groups to AL2023 if needed                  │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. CONTROL PLANE UPGRADE                                       │
│  • Calls update_cluster_version (one minor version up)          │
│  • Polls every 30s until status returns to ACTIVE               │
│  • Typically takes 8-15 minutes                                 │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. ADD-ON UPDATES                                              │
│  • Updates coredns, kube-proxy, vpc-cni to latest compatible    │
│  • Waits for each add-on to reach ACTIVE before proceeding      │
│  • Skips add-ons already at the latest version                  │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. MANAGED NODE GROUP ROLLING UPGRADE                          │
│  • For AL2023 groups: triggers update_nodegroup_version          │
│  • For AL2 groups: full migration (create new → drain → delete) │
│  • Respects PodDisruptionBudgets (force=False)                  │
│  • Polls until each node group returns to ACTIVE                │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. SELF-MANAGED NODE GROUP ROLLING UPGRADE                     │
│  • Discovers ASGs via kubernetes.io/cluster/<name> tag           │
│  • Resolves AMI (custom tag → SSM fallback)                     │
│  • Creates new launch template version with updated AMI         │
│  • Starts ASG instance refresh (90% min healthy)                │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. STATUS REPORT                                               │
│  • Prints cluster version, node groups, nodes, and pods         │
│  • Confirms all components are aligned to target version        │
└─────────────────────────────────────────────────────────────────┘
```

## Step Details

### 0. Pre-flight Checks

Before upgrading the control plane, the script validates:

1. **Target version support** — Queries `describe_addon_versions` to confirm the next minor version is available in the region. If not, it assumes the cluster is already on the latest and only aligns node groups/add-ons.

2. **Node group version alignment** — EKS requires all managed node groups to be at the same version as the control plane before allowing an upgrade. If any are behind, the script upgrades them first.

3. **Node availability** — Add-ons like CoreDNS need at least one node to schedule on. If all node groups have `desiredSize=0`, the script scales the first one up automatically.

4. **AL2 detection** — If a node group uses a deprecated AL2 AMI type, it cannot be upgraded in-place. The script triggers a full migration to AL2023 instead.

### 1. Control Plane Upgrade

- Calls `update_cluster_version` to initiate the upgrade.
- Polls cluster status every 30 seconds until it returns to `ACTIVE` with the new version.
- Raises an error and exits if status reaches `FAILED`.
- This step is fully managed by AWS — no nodes are affected yet.

### 2. Add-on Updates

Updates the three core EKS-managed add-ons:

| Add-on | Purpose |
|--------|---------|
| `coredns` | Cluster DNS resolution |
| `kube-proxy` | Service networking / iptables rules |
| `vpc-cni` | Pod networking (ENI attachment) |

- Queries the latest compatible version for the new cluster version.
- Skips add-ons already at the latest version.
- Uses `resolveConflicts=OVERWRITE` to apply updates even if configs have drifted.
- Waits for each add-on to reach `ACTIVE` status (5-minute timeout).

### 3. Managed Node Groups

Two paths depending on AMI type:

#### Standard Upgrade (AL2023 node groups)

- Calls `update_nodegroup_version` which triggers a rolling replacement.
- EKS launches new nodes with the updated AMI, cordons/drains old nodes, then terminates them.
- `force=False` ensures PodDisruptionBudgets are respected.
- Polls until status returns to `ACTIVE`.

#### AL2 → AL2023 Migration

When a node group uses a deprecated AL2 AMI type (`AL2_x86_64`, `AL2_x86_64_GPU`, `AL2_ARM_64`), in-place upgrades are not possible. The script performs a full migration:

1. **Create** a new node group with the AL2023 equivalent AMI type, copying all config (subnets, instance types, scaling, taints, labels, tags).
2. **Wait** for the new node group to become `ACTIVE`.
3. **Cordon** all old nodes (mark unschedulable).
4. **Drain** all old nodes (evict pods gracefully with 60s grace period, 300s timeout).
5. **Verify** pods are running on new nodes (displays a table for visual confirmation).
6. **Approve** — prompts for manual confirmation before deleting the old node group.
7. **Delete** the old AL2 node group.

The AL2 to AL2023 AMI type mapping:

| AL2 Type | AL2023 Equivalent |
|----------|-------------------|
| `AL2_x86_64` | `AL2023_x86_64_STANDARD` |
| `AL2_x86_64_GPU` | `AL2023_x86_64_NVIDIA` |
| `AL2_ARM_64` | `AL2023_ARM_64_STANDARD` |

### 4. Self-Managed Node Groups

#### Discovery

Identifies self-managed node groups by finding Auto Scaling Groups tagged with `kubernetes.io/cluster/<cluster-name>` that are **not** owned by EKS managed node groups.

#### AMI Resolution (priority order)

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | CLI argument | Explicit AMI ID passed as the third argument |
| 2 | EC2 tag lookup | Queries your account for AMIs tagged with `eks-version=<target>` and `custom-eks-ami=true`, picks the newest |
| 3 | SSM Parameter Store | Falls back to the AWS-published EKS-optimized AL2023 AMI |

#### Rolling Replacement

- Creates a new launch template version with the resolved AMI.
- Updates the ASG to reference the new launch template version.
- Starts an instance refresh with:
  - `MinHealthyPercentage: 90` — at least 90% of instances remain healthy during rollout.
  - `InstanceWarmup: 300` — 5-minute warmup before new instances count as healthy.
- Polls instance refresh status until completion.

Supports ASGs using:
- Direct launch templates
- Mixed instances policies

Warns (but does not fail) if an ASG still uses a legacy launch configuration.

### 5. Status Report

After all upgrades complete, prints a formatted report showing:
- Cluster name, version, status, platform version, endpoint type
- All node groups with version, AMI type, status, and scaling config
- All nodes with instance ID, status, and kubelet version
- All pods with namespace, name, status, and node placement

## IMDSv2 Enforcement

For accounts with `httpTokensEnforced` enabled, the script automatically creates a launch template with `HttpTokens=required` when creating new node groups during AL2→AL2023 migrations. This ensures nodes can launch without hitting the IMDSv1 restriction.

If an existing launch template has `HttpTokens=optional`, you'll need to create a new version with `HttpTokens=required` and update the node group manually (or the script will fail with an `InvalidRequestException`).

## Prerequisites

- Python 3.8+
- `boto3` installed (`pip install boto3`)
- `kubectl` configured and pointing at the target cluster (required for drain/cordon operations and status reporting)
- AWS credentials configured with the following permissions:

### Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:UpdateClusterVersion",
        "eks:ListNodegroups",
        "eks:DescribeNodegroup",
        "eks:UpdateNodegroupVersion",
        "eks:UpdateNodegroupConfig",
        "eks:CreateNodegroup",
        "eks:DeleteNodegroup",
        "eks:DescribeAddon",
        "eks:DescribeAddonVersions",
        "eks:UpdateAddon",
        "ec2:DescribeImages",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:CreateLaunchTemplate",
        "ec2:CreateLaunchTemplateVersion",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:StartInstanceRefresh",
        "autoscaling:DescribeInstanceRefreshes",
        "ssm:GetParameter"
      ],
      "Resource": "*"
    }
  ]
}
```

## Custom AMI Integration

If you build custom EKS node AMIs (e.g., with Packer), tag them with:

```
eks-version = "1.34"
custom-eks-ami = "true"
```

The script will automatically discover and use the latest matching AMI for the target version. No CLI argument needed.

## Important Notes

- The script upgrades **one minor version** per run. Kubernetes does not support skipping minor versions.
- Managed node group upgrades respect PodDisruptionBudgets for graceful pod eviction.
- Self-managed node group upgrades use ASG instance refresh, which replaces instances in batches while maintaining availability.
- The default fallback AMI is **Amazon Linux 2023** (AL2023), as AL2 has reached end of standard support.
- AL2 → AL2023 migration requires **manual approval** before deleting the old node group. This is a safety gate to verify pods are healthy on new nodes.
- If the target version is not yet available in the region, the script will still align node groups and add-ons to the current version.
- The script will auto-scale a node group from 0 if all groups are scaled down (add-ons need nodes to schedule on).

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `InvalidRequestException: httpTokensEnforced` | Account requires IMDSv2 but launch template has `HttpTokens=optional` | Create new launch template version with `HttpTokens=required` |
| Control plane upgrade stuck | AWS-side issue, usually resolves within 30 min | Wait, or check AWS Health Dashboard |
| Node group update stuck in UPDATING | Node drain blocked by PDB or stuck pod | Check `kubectl get pdb -A` and stuck pods |
| Add-on timeout | Add-on waiting for nodes to schedule on | Ensure at least one node group has `desiredSize > 0` |
| `ResourceNotFoundException` for node group | Node group was deleted/renamed during run | Re-run the script |
