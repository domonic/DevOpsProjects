#!/usr/bin/env python3
"""
EKS Cluster Upgrade — Control Plane + Data Plane (zero downtime)

This script automates the full EKS cluster upgrade lifecycle:
  1. Pre-flight validation (version alignment, node availability, AL2 detection)
  2. Control plane version upgrade (one minor version at a time)
  3. Core add-on updates (coredns, kube-proxy, vpc-cni)
  4. Managed node group rolling upgrades (or AL2→AL2023 migration)
  5. Self-managed node group rolling upgrades (launch template + instance refresh)

Run repeatedly for multi-version jumps (e.g., 1.28 → 1.29 → 1.30).

Usage:
  python3 upgrade.py <cluster-name> <region> [custom-ami-id]

Requirements:
  - boto3, kubectl configured for the target cluster
  - IAM permissions for EKS, EC2, ASG, and SSM operations
  - For AL2→AL2023 migrations: manual approval is required before old node group deletion
"""

import boto3
import subprocess
import time
import sys

# ─── CLI Arguments ────────────────────────────────────────────────────────────
CLUSTER_NAME = sys.argv[1] if len(sys.argv) > 1 else "my-cluster"
REGION = sys.argv[2] if len(sys.argv) > 2 else "eu-west-2"
CUSTOM_AMI = sys.argv[3] if len(sys.argv) > 3 else None  # Optional: explicit AMI override for self-managed nodes

# ─── AWS Service Clients ──────────────────────────────────────────────────────
eks = boto3.client("eks", region_name=REGION)
ec2 = boto3.client("ec2", region_name=REGION)
asg_client = boto3.client("autoscaling", region_name=REGION)
ssm = boto3.client("ssm", region_name=REGION)


# ═══════════════════════════════════════════════════════════════════════════════
# VERSION HELPERS
# ═══════════════════════════════════════════════════════════════════════════════


def get_cluster_version():
    """Fetch the current Kubernetes version of the EKS control plane."""
    resp = eks.describe_cluster(name=CLUSTER_NAME)
    return resp["cluster"]["version"]


def get_next_version(current):
    """Calculate the next minor version (e.g., '1.33' → '1.34')."""
    major, minor = current.split(".")
    return f"{major}.{int(minor) + 1}"


def validate_target_version(target):
    """
    Check that the target version is supported by EKS in this region.
    Uses describe_addon_versions as a proxy — if add-ons exist for the version,
    it's a valid EKS version. Returns False if the version isn't available yet.
    """
    try:
        resp = eks.describe_addon_versions(kubernetesVersion=target)
        # If the API returns add-ons, the version is valid
        return len(resp.get("addons", [])) > 0
    except Exception:
        return False


# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: CONTROL PLANE UPGRADE
# ═══════════════════════════════════════════════════════════════════════════════


def upgrade_control_plane(target_version):
    """
    Initiate and wait for the EKS control plane version upgrade.
    This is a non-disruptive operation — the API server remains available
    during the upgrade (brief periods of degraded performance are possible).
    Typically takes 8-15 minutes.
    """
    print(f"⏳ Upgrading control plane to {target_version}...")
    eks.update_cluster_version(name=CLUSTER_NAME, version=target_version)

    # Wait for upgrade to complete
    while True:
        resp = eks.describe_cluster(name=CLUSTER_NAME)
        status = resp["cluster"]["status"]
        current_version = resp["cluster"]["version"]
        if status == "ACTIVE" and current_version == target_version:
            print(f"✓ Control plane upgraded to {target_version}")
            return
        elif status == "FAILED":
            raise RuntimeError("Control plane upgrade failed")
        print(f"  Status: {status}, version: {current_version}... waiting 30s")
        time.sleep(30)


# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: ADD-ON UPDATES
# ═══════════════════════════════════════════════════════════════════════════════


def update_addons(target_version):
    """
    Update core EKS add-ons to the latest version compatible with the target
    Kubernetes version. Processes each add-on sequentially to avoid conflicts.
    Uses OVERWRITE to resolve any config drift from manual edits.
    Skips add-ons that are already at the latest version.
    """
    addons = ["coredns", "kube-proxy", "vpc-cni"]
    any_updated = False

    for addon in addons:
        try:
            # Check current add-on version
            try:
                current_addon = eks.describe_addon(
                    clusterName=CLUSTER_NAME, addonName=addon
                )
                current_version = current_addon["addon"]["addonVersion"]
            except eks.exceptions.ResourceNotFoundException:
                print(f"  {addon}: not installed, skipping")
                continue

            # Get latest compatible version
            versions = eks.describe_addon_versions(
                kubernetesVersion=target_version, addonName=addon
            )
            latest = versions["addons"][0]["addonVersions"][0]["addonVersion"]

            # Skip if already on latest
            if current_version == latest:
                print(f"  ✓ {addon} already at {latest}")
                continue

            # Wait for add-on to be in a stable state before updating
            wait_for_addon_ready(addon)

            print(f"  Updating {addon}: {current_version} → {latest}")
            eks.update_addon(
                clusterName=CLUSTER_NAME,
                addonName=addon,
                addonVersion=latest,
                resolveConflicts="OVERWRITE",
            )
            any_updated = True

            # Wait for this add-on update to complete before proceeding
            wait_for_addon_ready(addon)

        except Exception as e:
            print(f"  ⚠️  {addon}: {e}")

    if any_updated:
        print("✓ Add-ons updated")
    else:
        print("✓ All add-ons already at latest compatible versions")


def wait_for_addon_ready(addon_name, timeout=300):
    """Wait for an add-on to reach ACTIVE status before proceeding."""
    elapsed = 0
    while elapsed < timeout:
        try:
            resp = eks.describe_addon(
                clusterName=CLUSTER_NAME, addonName=addon_name
            )
            status = resp["addon"]["status"]
            if status == "ACTIVE":
                return
            elif status in ("CREATE_FAILED", "DELETE_FAILED"):
                print(f"  ⚠️  {addon_name} is in {status} state")
                return
            time.sleep(15)
            elapsed += 15
        except eks.exceptions.ResourceNotFoundException:
            # Add-on not installed, nothing to wait for
            return
    print(f"  ⚠️  Timed out waiting for {addon_name} to stabilize")


# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: MANAGED NODE GROUP UPGRADES
# ═══════════════════════════════════════════════════════════════════════════════


def rolling_upgrade_managed_nodegroups():
    """
    Upgrade all managed node groups to match the cluster version.
    Two strategies:
      - AL2023 groups: in-place rolling update via update_nodegroup_version
      - AL2 groups: full migration (create AL2023 replacement → drain → delete old)
    Skips node groups already at the target version.
    """
    resp = eks.list_nodegroups(clusterName=CLUSTER_NAME)
    nodegroups = resp["nodegroups"]

    if not nodegroups:
        print("  No managed node groups found.")
        return

    cluster_version = get_cluster_version()

    for ng in nodegroups:
        desc = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=ng)
        ng_version = desc["nodegroup"].get("version", "")
        ami_type = desc["nodegroup"].get("amiType", "")

        # Skip if already at cluster version
        if ng_version == cluster_version:
            print(f"  ✓ {ng} already at {cluster_version}")
            continue

        # Detect deprecated AL2 AMI types that need migration to AL2023
        if ami_type in ("AL2_x86_64", "AL2_x86_64_GPU", "AL2_ARM_64"):
            print(f"⏳ Migrating node group (AL2 → AL2023): {ng}")
            migrate_nodegroup_to_al2023(ng, desc["nodegroup"])
        else:
            print(f"⏳ Rolling upgrade (managed): {ng}")
            upgrade_single_managed_nodegroup(ng)


def upgrade_single_managed_nodegroup(ng):
    """
    Perform a rolling version upgrade on a single managed node group.
    EKS handles the orchestration: launch new node → cordon old → drain → terminate.
    force=False ensures PodDisruptionBudgets are respected during drain.
    """
    try:
        eks.update_nodegroup_version(
            clusterName=CLUSTER_NAME,
            nodegroupName=ng,
            force=False,  # Respects PodDisruptionBudgets
        )
    except Exception as e:
        print(f"  ⚠️  Failed to update {ng}: {e}")
        return

    # Wait for node group update to complete
    while True:
        desc = eks.describe_nodegroup(
            clusterName=CLUSTER_NAME, nodegroupName=ng
        )
        status = desc["nodegroup"]["status"]

        if status == "ACTIVE":
            print(f"✓ Managed node group {ng} upgraded")
            break
        elif status == "DEGRADED":
            print(f"⚠️  Managed node group {ng} degraded — check console")
            break
        print(f"  {ng} status: {status}... waiting 30s")
        time.sleep(30)


# ─── AL2 → AL2023 Migration ───────────────────────────────────────────────────
# EKS deprecated AL2 AMIs. Node groups using AL2 cannot be upgraded in-place
# to newer Kubernetes versions. Instead, we create a replacement node group
# with the AL2023 equivalent, migrate workloads, then delete the old one.
# ──────────────────────────────────────────────────────────────────────────────

# Mapping from AL2 AMI types to their AL2023 equivalents
AL2_TO_AL2023_AMI_TYPE = {
    "AL2_x86_64": "AL2023_x86_64_STANDARD",
    "AL2_x86_64_GPU": "AL2023_x86_64_NVIDIA",
    "AL2_ARM_64": "AL2023_ARM_64_STANDARD",
}


def migrate_nodegroup_to_al2023(old_ng_name, nodegroup_config):
    """
    Migrate a managed node group from AL2 to AL2023 by:
    1. Creating a new node group with AL2023 AMI type (same config)
    2. Waiting for the new node group to become ACTIVE
    3. Cordoning old nodes and draining pods to new nodes
    4. Verifying pods are running on new nodes
    5. Requesting manual approval before deleting old node group
    6. Deleting the old AL2 node group

    This ensures zero downtime — pods are verified healthy on new nodes
    before old nodes are removed.
    """
    old_ami_type = nodegroup_config.get("amiType", "AL2_x86_64")
    new_ami_type = AL2_TO_AL2023_AMI_TYPE.get(old_ami_type, "AL2023_x86_64_STANDARD")
    new_ng_name = f"{old_ng_name}-al2023"

    # Truncate if name exceeds EKS 63-char limit
    if len(new_ng_name) > 63:
        new_ng_name = new_ng_name[:63]

    print(f"  Old AMI type: {old_ami_type}")
    print(f"  New AMI type: {new_ami_type}")
    print(f"  New node group name: {new_ng_name}")

    create_params = build_nodegroup_create_params(
        new_ng_name, new_ami_type, nodegroup_config
    )

    # Step 1: Create new AL2023 node group
    if not create_replacement_nodegroup(new_ng_name, create_params):
        return

    # Step 2: Wait for new node group to become ACTIVE
    if not wait_for_nodegroup_active(new_ng_name):
        return

    # Step 3: Cordon old nodes and drain pods to new nodes
    cordon_and_drain_old_nodes(old_ng_name)

    # Step 4: Verify pods are running on new nodes
    show_pods_on_new_nodes(new_ng_name)

    # Step 5: Request manual approval before deleting old node group
    if not request_deletion_approval(old_ng_name):
        print(f"  ⚠️  Skipping deletion of {old_ng_name} — manual cleanup required")
        return

    # Step 6: Delete old AL2 node group and wait for removal
    delete_old_nodegroup(old_ng_name)

    print(f"✓ Node group migrated: {old_ng_name} (AL2) → {new_ng_name} (AL2023)")


def cordon_and_drain_old_nodes(old_ng_name):
    """Cordon and drain all nodes belonging to the old node group."""
    print(f"\n  ⏳ Cordoning and draining old nodes ({old_ng_name})...")

    # Get nodes belonging to the old node group
    old_nodes = get_nodes_for_nodegroup(old_ng_name)
    if not old_nodes:
        print("  No old nodes found to drain (may already be scaled to 0)")
        return

    for node in old_nodes:
        # Cordon: mark node as unschedulable
        print(f"    Cordoning {node}...")
        subprocess.run(
            ["kubectl", "cordon", node],
            capture_output=True, text=True, timeout=30
        )

    for node in old_nodes:
        # Drain: evict pods gracefully
        print(f"    Draining {node}...")
        result = subprocess.run(
            ["kubectl", "drain", node,
             "--ignore-daemonsets",
             "--delete-emptydir-data",
             "--grace-period=60",
             "--timeout=300s"],
            capture_output=True, text=True, timeout=360
        )
        if result.returncode != 0:
            print(f"    ⚠️  Drain warning for {node}: {result.stderr.strip()}")
        else:
            print(f"    ✓ {node} drained")

    print(f"  ✓ All old nodes cordoned and drained")


def get_nodes_for_nodegroup(ng_name):
    """Get node names belonging to a specific EKS node group."""
    try:
        result = subprocess.run(
            ["kubectl", "get", "nodes",
             "-l", f"eks.amazonaws.com/nodegroup={ng_name}",
             "-o", "jsonpath={.items[*].metadata.name}"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    return []


def show_pods_on_new_nodes(new_ng_name):
    """Display pods running on the new node group's nodes for verification."""
    print(f"\n  ⏳ Waiting for pods to schedule on new nodes ({new_ng_name})...")
    time.sleep(30)  # Give scheduler time to place pods

    new_nodes = get_nodes_for_nodegroup(new_ng_name)
    if not new_nodes:
        print("  ⚠️  No new nodes found — pods may still be scheduling")
        return

    print(f"\n  ┌─ Pods on new nodes ({new_ng_name}) ─────────────────────────────────────────┐")
    print(f"  │  {'Namespace':<18} {'Pod':<42} {'Status':<12} {'Node'}")
    print(f"  │  " + "─" * 80)

    try:
        for node in new_nodes:
            result = subprocess.run(
                ["kubectl", "get", "pods", "--all-namespaces",
                 "--field-selector", f"spec.nodeName={node}",
                 "-o", "custom-columns=NS:.metadata.namespace,"
                 "NAME:.metadata.name,STATUS:.status.phase",
                 "--no-headers"],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0 and result.stdout.strip():
                for line in result.stdout.strip().split("\n"):
                    parts = line.split()
                    if len(parts) >= 3:
                        short_node = node.split(".")[0]
                        print(f"  │  {parts[0]:<18} {parts[1]:<42} {parts[2]:<12} {short_node}")
    except (subprocess.TimeoutExpired, FileNotFoundError):
        print("  │  Unable to query pods (kubectl not available)")

    print(f"  └──────────────────────────────────────────────────────────────────────────────────┘")


def request_deletion_approval(old_ng_name):
    """Ask for manual approval before deleting the old node group."""
    print(f"\n  ╔══════════════════════════════════════════════════════════════════╗")
    print(f"  ║  APPROVAL REQUIRED                                               ║")
    print(f"  ║  Ready to delete old node group: {old_ng_name:<30} ║")
    print(f"  ║  Verify pods above are healthy before proceeding.                ║")
    print(f"  ╚══════════════════════════════════════════════════════════════════╝")

    try:
        response = input(f"\n  Delete old node group '{old_ng_name}'? [y/N]: ").strip().lower()
        return response in ("y", "yes")
    except (EOFError, KeyboardInterrupt):
        print("\n  No input received — skipping deletion")
        return False


def build_nodegroup_create_params(new_ng_name, new_ami_type, nodegroup_config):
    """Build the create_nodegroup parameters from existing node group config."""
    scaling = nodegroup_config.get("scalingConfig", {})
    create_params = {
        "clusterName": CLUSTER_NAME,
        "nodegroupName": new_ng_name,
        "nodeRole": nodegroup_config["nodeRole"],
        "subnets": nodegroup_config["subnets"],
        "amiType": new_ami_type,
        "instanceTypes": nodegroup_config.get("instanceTypes", []),
        "scalingConfig": {
            "minSize": scaling.get("minSize", 1),
            "maxSize": scaling.get("maxSize", 3),
            "desiredSize": scaling.get("desiredSize", 2),
        },
        "capacityType": nodegroup_config.get("capacityType", "ON_DEMAND"),
    }

    if nodegroup_config.get("diskSize"):
        create_params["diskSize"] = nodegroup_config["diskSize"]

    # Copy user labels (exclude eksctl-managed labels)
    labels = nodegroup_config.get("labels", {})
    user_labels = {
        k: v for k, v in labels.items()
        if not k.startswith("alpha.eksctl.io/")
    }
    if user_labels:
        create_params["labels"] = user_labels

    taints = nodegroup_config.get("taints")
    if taints:
        create_params["taints"] = taints

    # Filter out AWS-managed tags (aws: prefix) — cannot be set by users
    tags = nodegroup_config.get("tags", {})
    user_tags = {
        k: v for k, v in tags.items()
        if not k.lower().startswith("aws:")
    }
    if user_tags:
        create_params["tags"] = user_tags

    # Carry over launch template if configured
    launch_template = nodegroup_config.get("launchTemplate")
    if launch_template:
        create_params["launchTemplate"] = {
            "id": launch_template.get("id"),
            "version": launch_template.get("version"),
        }
        # When using a launch template, AMI type is set in the template
        create_params.pop("amiType", None)

    return create_params


def create_replacement_nodegroup(new_ng_name, create_params):
    """Create the replacement AL2023 node group. Returns True on success."""
    # If no launch template is specified, create one that enforces IMDSv2
    if "launchTemplate" not in create_params:
        lt = create_imdsv2_launch_template(new_ng_name)
        if lt:
            create_params["launchTemplate"] = lt
            # amiType is set at the nodegroup level, not in the launch template
            # so we keep it in create_params

    try:
        eks.create_nodegroup(**create_params)
        print(f"  Creating new node group {new_ng_name}...")
        return True
    except eks.exceptions.ResourceInUseException:
        print(f"  Node group {new_ng_name} already exists, checking status...")
        return True
    except Exception as e:
        print(f"  ⚠️  Failed to create replacement node group: {e}")
        return False


def create_imdsv2_launch_template(ng_name):
    """
    Create a minimal launch template that enforces IMDSv2 (HttpTokens=required).
    Required for accounts with httpTokensEnforced enabled.
    Returns the launch template dict for create_nodegroup, or None on failure.
    """
    lt_name = f"{CLUSTER_NAME}-{ng_name}-lt"
    # Truncate to 128 chars (launch template name limit)
    if len(lt_name) > 128:
        lt_name = lt_name[:128]

    try:
        resp = ec2.create_launch_template(
            LaunchTemplateName=lt_name,
            LaunchTemplateData={
                "MetadataOptions": {
                    "HttpTokens": "required",
                    "HttpPutResponseHopLimit": 2,
                    "HttpEndpoint": "enabled",
                },
            },
            TagSpecifications=[
                {
                    "ResourceType": "launch-template",
                    "Tags": [
                        {"Key": "eks-cluster-name", "Value": CLUSTER_NAME},
                        {"Key": "eks-nodegroup-name", "Value": ng_name},
                    ],
                }
            ],
        )
        lt_id = resp["LaunchTemplate"]["LaunchTemplateId"]
        version = str(resp["LaunchTemplate"]["LatestVersionNumber"])
        print(f"  Created launch template {lt_id} (IMDSv2 enforced)")
        return {"id": lt_id, "version": version}
    except ec2.exceptions.ClientError as e:
        # If template already exists, look it up
        if "InvalidLaunchTemplateName.AlreadyExistsException" in str(e):
            resp = ec2.describe_launch_templates(
                LaunchTemplateNames=[lt_name]
            )
            lt = resp["LaunchTemplates"][0]
            lt_id = lt["LaunchTemplateId"]
            version = str(lt["LatestVersionNumber"])
            print(f"  Using existing launch template {lt_id}")
            return {"id": lt_id, "version": version}
        print(f"  ⚠️  Failed to create launch template: {e}")
        return None
    except Exception as e:
        print(f"  ⚠️  Failed to create launch template: {e}")
        return None


def wait_for_nodegroup_active(ng_name):
    """Wait for a node group to reach ACTIVE status. Returns True on success."""
    while True:
        try:
            desc = eks.describe_nodegroup(
                clusterName=CLUSTER_NAME, nodegroupName=ng_name
            )
            status = desc["nodegroup"]["status"]
            if status == "ACTIVE":
                print(f"  ✓ New node group {ng_name} is ACTIVE")
                return True
            if status in ("CREATE_FAILED", "DEGRADED"):
                print(f"  ⚠️  New node group {ng_name} status: {status}")
                print("  Aborting migration — old node group preserved")
                return False
            print(f"  {ng_name} status: {status}... waiting 30s")
        except Exception as e:
            print(f"  Waiting for node group creation... ({e})")
        time.sleep(30)


def delete_old_nodegroup(old_ng_name):
    """Delete the old node group and wait for removal."""
    print(f"  Deleting old node group {old_ng_name}...")
    try:
        eks.delete_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=old_ng_name)
    except Exception as e:
        print(f"  ⚠️  Failed to delete old node group: {e}")
        return

    # Wait for old node group to be fully removed
    while True:
        try:
            desc = eks.describe_nodegroup(
                clusterName=CLUSTER_NAME, nodegroupName=old_ng_name
            )
            status = desc["nodegroup"]["status"]
            print(f"  {old_ng_name} status: {status}... waiting 30s")
            time.sleep(30)
        except eks.exceptions.ResourceNotFoundException:
            break
        except Exception:
            break


# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: SELF-MANAGED NODE GROUP UPGRADES
# ═══════════════════════════════════════════════════════════════════════════════


def get_eks_optimized_ami(target_version):
    """
    Resolve the AMI to use for self-managed node groups.

    Priority:
    1. Explicit CLI override (CUSTOM_AMI argument)
    2. Custom AMI found via EC2 tags (eks-version + custom-eks-ami)
    3. AWS-published EKS-optimized AMI from SSM Parameter Store

    This allows teams with custom AMI pipelines (e.g., Packer + CIS hardening)
    to have their AMIs automatically discovered without passing IDs manually.
    """
    # 1. Explicit override
    if CUSTOM_AMI:
        print(f"  Using explicit AMI override: {CUSTOM_AMI}")
        return CUSTOM_AMI

    # 2. Tag-based lookup for custom AMIs
    # Expects your AMI pipeline to tag images with:
    #   - eks-version: "1.XX"
    #   - custom-eks-ami: "true"
    custom_ami = find_custom_ami_by_tags(target_version)
    if custom_ami:
        return custom_ami

    # 3. Fallback to AWS EKS-optimized AMI
    return get_aws_eks_optimized_ami(target_version)


def find_custom_ami_by_tags(target_version):
    """
    Look up a custom AMI by tags. Returns the most recently created AMI
    matching the target Kubernetes version, or None if not found.

    Expected tags on your custom AMIs:
      - eks-version: "<major>.<minor>" (e.g., "1.30")
      - custom-eks-ami: "true"
    """
    try:
        resp = ec2.describe_images(
            Owners=["self"],
            Filters=[
                {"Name": "tag:eks-version", "Values": [target_version]},
                {"Name": "tag:custom-eks-ami", "Values": ["true"]},
                {"Name": "state", "Values": ["available"]},
            ],
        )
        images = resp.get("Images", [])
        if not images:
            return None

        # Sort by creation date descending, pick the newest
        images.sort(key=lambda img: img["CreationDate"], reverse=True)
        ami_id = images[0]["ImageId"]
        ami_name = images[0].get("Name", "unnamed")
        print(f"  Found custom AMI: {ami_id} ({ami_name})")
        return ami_id

    except Exception as e:
        print(f"  ⚠️  Custom AMI lookup failed: {e}")
        return None


def get_aws_eks_optimized_ami(target_version):
    """Retrieve the latest AWS-published EKS-optimized AL2023 AMI from SSM."""
    parameter_name = f"/aws/service/eks/optimized-ami/{target_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
    try:
        resp = ssm.get_parameter(Name=parameter_name)
        ami_id = resp["Parameter"]["Value"]
        print(f"  Using AWS EKS-optimized AL2023 AMI: {ami_id}")
        return ami_id
    except ssm.exceptions.ParameterNotFound:
        raise RuntimeError(
            f"Could not find EKS-optimized AL2023 AMI for version {target_version}"
        )


def find_self_managed_nodegroup_asgs():
    """
    Find Auto Scaling Groups that belong to self-managed node groups
    by looking for the kubernetes.io/cluster/<name> tag on ASGs that
    are NOT managed by EKS managed node groups.
    """
    managed_asgs = set()

    # Collect ASGs owned by managed node groups so we can exclude them
    resp = eks.list_nodegroups(clusterName=CLUSTER_NAME)
    for ng in resp["nodegroups"]:
        desc = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=ng)
        for resource in desc["nodegroup"].get("resources", {}).get("autoScalingGroups", []):
            managed_asgs.add(resource["name"])

    # Find all ASGs tagged for this cluster
    paginator = asg_client.get_paginator("describe_auto_scaling_groups")
    self_managed_asgs = []

    for page in paginator.paginate():
        for asg in page["AutoScalingGroups"]:
            asg_name = asg["AutoScalingGroupName"]
            if asg_name in managed_asgs:
                continue

            tags = {t["Key"]: t["Value"] for t in asg.get("Tags", [])}
            cluster_tag = f"kubernetes.io/cluster/{CLUSTER_NAME}"
            if cluster_tag in tags:
                self_managed_asgs.append(asg)

    return self_managed_asgs


def update_launch_template_ami(asg, ami_id):
    """
    Update the launch template (or launch config) used by the ASG
    to reference the new EKS-optimized AMI.
    Returns True if updated successfully, False otherwise.
    """
    lt = asg.get("LaunchTemplate")
    if lt:
        lt_id = lt["LaunchTemplateId"]
        lt_version = lt["Version"]

        # Describe current version to copy settings
        lt_desc = ec2.describe_launch_template_versions(
            LaunchTemplateId=lt_id, Versions=[lt_version]
        )
        current_data = lt_desc["LaunchTemplateVersions"][0]["LaunchTemplateData"]

        # Create new version with updated AMI
        current_data["ImageId"] = ami_id
        new_version = ec2.create_launch_template_version(
            LaunchTemplateId=lt_id,
            LaunchTemplateData=current_data,
            SourceVersion=lt_version,
        )
        new_version_number = str(
            new_version["LaunchTemplateVersion"]["VersionNumber"]
        )

        # Update ASG to use the new launch template version
        asg_client.update_auto_scaling_group(
            AutoScalingGroupName=asg["AutoScalingGroupName"],
            LaunchTemplate={
                "LaunchTemplateId": lt_id,
                "Version": new_version_number,
            },
        )
        print(f"  Updated launch template {lt_id} → version {new_version_number}")
        return True

    # Mixed instances policy with launch template
    mip = asg.get("MixedInstancesPolicy")
    if mip:
        lt_spec = mip["LaunchTemplate"]["LaunchTemplateSpecification"]
        lt_id = lt_spec["LaunchTemplateId"]
        lt_version = lt_spec.get("Version", "$Default")

        lt_desc = ec2.describe_launch_template_versions(
            LaunchTemplateId=lt_id, Versions=[lt_version]
        )
        current_data = lt_desc["LaunchTemplateVersions"][0]["LaunchTemplateData"]
        current_data["ImageId"] = ami_id

        new_version = ec2.create_launch_template_version(
            LaunchTemplateId=lt_id,
            LaunchTemplateData=current_data,
            SourceVersion=lt_version,
        )
        new_version_number = str(
            new_version["LaunchTemplateVersion"]["VersionNumber"]
        )

        lt_spec["Version"] = new_version_number
        asg_client.update_auto_scaling_group(
            AutoScalingGroupName=asg["AutoScalingGroupName"],
            MixedInstancesPolicy=mip,
        )
        print(f"  Updated launch template {lt_id} (MIP) → version {new_version_number}")
        return True

    print(f"  ⚠️  ASG {asg['AutoScalingGroupName']} uses a launch configuration — "
          "migrate to a launch template for automated AMI updates.")
    return False


def rolling_upgrade_self_managed_nodegroups(target_version):
    """
    Upgrade self-managed node groups by:
    1. Discovering ASGs tagged for this cluster (excluding EKS-managed ones)
    2. Resolving the correct AMI for the target version
    3. Creating a new launch template version with the updated AMI
    4. Starting an ASG instance refresh for zero-downtime rolling replacement

    Instance refresh maintains 90% healthy capacity during the rollout,
    replacing instances in batches with a 5-minute warmup period.
    """
    self_managed_asgs = find_self_managed_nodegroup_asgs()

    if not self_managed_asgs:
        print("  No self-managed node groups found.")
        return

    ami_id = get_eks_optimized_ami(target_version)

    for asg in self_managed_asgs:
        asg_name = asg["AutoScalingGroupName"]
        print(f"⏳ Rolling upgrade (self-managed): {asg_name}")

        # Update the launch template with the new AMI
        updated = update_launch_template_ami(asg, ami_id)
        if not updated:
            continue

        # Start instance refresh for zero-downtime rolling replacement
        try:
            asg_client.start_instance_refresh(
                AutoScalingGroupName=asg_name,
                Strategy="Rolling",
                Preferences={
                    "MinHealthyPercentage": 90,
                    "InstanceWarmup": 300,
                },
            )
            print(f"  Instance refresh started for {asg_name}")
        except asg_client.exceptions.InstanceRefreshInProgressException:
            print(f"  Instance refresh already in progress for {asg_name}")

        # Wait for instance refresh to complete
        while True:
            refreshes = asg_client.describe_instance_refreshes(
                AutoScalingGroupName=asg_name, MaxRecords=1
            )
            if not refreshes["InstanceRefreshes"]:
                break

            refresh = refreshes["InstanceRefreshes"][0]
            status = refresh["Status"]

            if status == "Successful":
                print(f"✓ Self-managed node group {asg_name} upgraded")
                break
            elif status in ("Cancelled", "Failed", "RollbackSuccessful", "RollbackFailed"):
                print(f"⚠️  Instance refresh for {asg_name} ended with status: {status}")
                break

            pct = refresh.get("PercentageComplete", 0)
            print(f"  {asg_name} refresh: {status} ({pct}% complete)... waiting 30s")
            time.sleep(30)


# ═══════════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKS
# ═══════════════════════════════════════════════════════════════════════════════


def ensure_nodegroups_match_cluster_version(current_version):
    """
    Ensure all managed node groups are running the same version as the
    control plane. EKS requires this before allowing a control plane upgrade.

    If a node group is behind, it will be upgraded (or migrated if AL2).
    Returns True if all node groups are aligned, False if any failed.
    """
    resp = eks.list_nodegroups(clusterName=CLUSTER_NAME)
    nodegroups = resp["nodegroups"]

    if not nodegroups:
        return True

    all_aligned = True
    for ng in nodegroups:
        desc = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=ng)
        ng_version = desc["nodegroup"].get("version", "")
        ami_type = desc["nodegroup"].get("amiType", "")

        if ng_version == current_version:
            continue

        print(f"  Node group {ng} is on {ng_version} and needs to be updated to match current cluster version {current_version}")

        # If it's an AL2 node group that can't be updated in-place, migrate it
        if ami_type in ("AL2_x86_64", "AL2_x86_64_GPU", "AL2_ARM_64"):
            print(f"⏳ Migrating {ng} (AL2 → AL2023) to match cluster version...")
            migrate_nodegroup_to_al2023(ng, desc["nodegroup"])
        else:
            print(f"⏳ Updating {ng} to match cluster version {current_version}...")
            upgrade_single_managed_nodegroup(ng)

        # Verify the node group (or its replacement) is now at the right version
        updated_ngs = eks.list_nodegroups(clusterName=CLUSTER_NAME)["nodegroups"]
        if ng not in updated_ngs:
            # Old node group was replaced — check replacement
            continue
        re_desc = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=ng)
        if re_desc["nodegroup"].get("version", "") != current_version:
            all_aligned = False

    return all_aligned


def ensure_nodes_available():
    """
    Ensure at least one managed node group has a non-zero desired size.
    Add-ons like CoreDNS require nodes to schedule on. If all node groups
    have desiredSize=0 (e.g., cluster autoscaler scaled everything down),
    this function scales the first node group up to provide scheduling capacity.

    This prevents add-on updates from hanging indefinitely waiting for pods
    to become schedulable.
    """
    resp = eks.list_nodegroups(clusterName=CLUSTER_NAME)
    nodegroups = resp["nodegroups"]

    if not nodegroups:
        return

    # Check if any node group already has nodes
    for ng in nodegroups:
        desc = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=ng)
        scaling = desc["nodegroup"].get("scalingConfig", {})
        if scaling.get("desiredSize", 0) > 0:
            return  # At least one group has nodes, we're good

    # All node groups have desiredSize=0 — scale up the first one
    first_ng = nodegroups[0]
    desc = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=first_ng)
    scaling = desc["nodegroup"].get("scalingConfig", {})
    min_size = scaling.get("minSize", 0)
    max_size = scaling.get("maxSize", 1)
    new_desired = max(min_size, 1) if min_size > 0 else min(2, max_size)

    if new_desired == 0:
        print("  ⚠️  All node groups have desiredSize=0 and minSize=0.")
        print("  Add-ons require at least one node. Scale a node group manually.")
        sys.exit(1)

    print(f"  Scaling {first_ng} to desiredSize={new_desired} for add-on scheduling...")
    eks.update_nodegroup_config(
        clusterName=CLUSTER_NAME,
        nodegroupName=first_ng,
        scalingConfig={
            "minSize": min_size if min_size > 0 else new_desired,
            "maxSize": max_size,
            "desiredSize": new_desired,
        },
    )

    # Wait for node group to stabilize
    while True:
        desc = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=first_ng)
        status = desc["nodegroup"]["status"]
        if status == "ACTIVE":
            print(f"  ✓ {first_ng} scaled up, nodes available")
            return
        print(f"  {first_ng} status: {status}... waiting 30s")
        time.sleep(30)


# ═══════════════════════════════════════════════════════════════════════════════
# STATUS REPORTING
# ═══════════════════════════════════════════════════════════════════════════════


def print_cluster_status():
    """Print a summary table showing cluster, node groups, instances, and pod status."""
    width = 100
    print("\n")
    print("╔" + "═" * (width - 2) + "╗")
    print("║" + "CLUSTER STATUS REPORT".center(width - 2) + "║")
    print("╚" + "═" * (width - 2) + "╝")

    print_cluster_info()
    print_nodegroup_info()
    print_node_info()
    print_pod_info()

    print("\n" + "─" * width)


def print_cluster_info():
    """Print cluster version and status."""
    resp = eks.describe_cluster(name=CLUSTER_NAME)
    cluster = resp["cluster"]

    print("\n┌─ Cluster ─────────────────────────────────────────────────────────────────────┐")
    print(f"│  {'Name:':<20} {CLUSTER_NAME}")
    print(f"│  {'Version:':<20} {cluster['version']}")
    print(f"│  {'Status:':<20} {cluster['status']}")
    print(f"│  {'Platform:':<20} {cluster.get('platformVersion', 'N/A')}")
    print(f"│  {'Endpoint:':<20} {'Public' if cluster.get('resourcesVpcConfig', {}).get('endpointPublicAccess') else 'Private'}")
    print("└──────────────────────────────────────────────────────────────────────────────────┘")


def print_nodegroup_info():
    """Print node group details table."""
    ng_resp = eks.list_nodegroups(clusterName=CLUSTER_NAME)
    nodegroups = ng_resp["nodegroups"]

    print("\n┌─ Node Groups ────────────────────────────────────────────────────────────────────┐")

    if not nodegroups:
        print("│  No managed node groups found.")
        print("└──────────────────────────────────────────────────────────────────────────────────┘")
        return

    # Header
    print(f"│  {'Name':<35} {'Ver':<6} {'AMI Type':<22} {'Status':<10} {'Min':<5} {'Max':<5} {'Desired'}")
    print("│  " + "─" * 85)

    for ng in nodegroups:
        desc = eks.describe_nodegroup(clusterName=CLUSTER_NAME, nodegroupName=ng)
        ngd = desc["nodegroup"]
        scaling = ngd.get("scalingConfig", {})
        print(f"│  {ng:<35} {ngd.get('version', '-'):<6} "
              f"{ngd.get('amiType', '-'):<22} {ngd['status']:<10} "
              f"{scaling.get('minSize', 0):<5} {scaling.get('maxSize', 0):<5} "
              f"{scaling.get('desiredSize', 0)}")

    print("└──────────────────────────────────────────────────────────────────────────────────┘")


def print_node_info():
    """Print node instances via kubectl."""
    print("\n┌─ Nodes ───────────────────────────────────────────────────────────────────────────┐")

    try:
        result = subprocess.run(
            ["kubectl", "get", "nodes", "-o",
             "custom-columns=NAME:.metadata.name,"
             "INSTANCE:.spec.providerID,"
             "STATUS:.status.conditions[-1].type,"
             "VERSION:.status.nodeInfo.kubeletVersion",
             "--no-headers"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0 or not result.stdout.strip():
            print("│  No nodes found or kubectl not configured for this cluster")
            print("└──────────────────────────────────────────────────────────────────────────────────┘")
            return

        # Header
        print(f"│  {'Node Name':<45} {'Instance ID':<22} {'Status':<10} {'Version'}")
        print("│  " + "─" * 85)

        for line in result.stdout.strip().split("\n"):
            parts = line.split()
            if len(parts) >= 4:
                node_name = parts[0]
                provider_id = parts[1]
                instance_id = provider_id.split("/")[-1] if "/" in provider_id else provider_id
                status = parts[2]
                version = parts[3]
                print(f"│  {node_name:<45} {instance_id:<22} {status:<10} {version}")

    except (subprocess.TimeoutExpired, FileNotFoundError):
        print("│  Unable to reach cluster (kubectl not configured or unreachable)")

    print("└──────────────────────────────────────────────────────────────────────────────────┘")


def print_pod_info():
    """Print pod status via kubectl."""
    print("\n┌─ Pods ────────────────────────────────────────────────────────────────────────────┐")

    try:
        result = subprocess.run(
            ["kubectl", "get", "pods", "--all-namespaces", "-o",
             "custom-columns=NAMESPACE:.metadata.namespace,"
             "NAME:.metadata.name,"
             "STATUS:.status.phase,"
             "NODE:.spec.nodeName",
             "--no-headers"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0 or not result.stdout.strip():
            print("│  No pods found or kubectl not configured for this cluster")
            print("└──────────────────────────────────────────────────────────────────────────────────┘")
            return

        # Header
        print(f"│  {'Namespace':<18} {'Pod':<45} {'Status':<12} {'Node'}")
        print("│  " + "─" * 85)

        for line in result.stdout.strip().split("\n"):
            parts = line.split()
            if len(parts) >= 4:
                print(f"│  {parts[0]:<18} {parts[1]:<45} {parts[2]:<12} {parts[3]}")
            elif len(parts) == 3:
                print(f"│  {parts[0]:<18} {parts[1]:<45} {parts[2]:<12} {'<none>'}")

    except (subprocess.TimeoutExpired, FileNotFoundError):
        print("│  Unable to reach cluster (kubectl not configured or unreachable)")

    print("└──────────────────────────────────────────────────────────────────────────────────┘")


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════


def main():
    """
    Main orchestration function. Executes the full upgrade workflow:
      0. Pre-flight checks (version alignment, node availability)
      1. Control plane upgrade
      2. Add-on updates
      3. Managed node group rolling upgrades
      4. Self-managed node group rolling upgrades
      5. Final status report

    If the target version is not yet available (cluster already on latest),
    the script skips the control plane upgrade but still aligns add-ons
    and node groups to the current version.
    """
    current = get_cluster_version()
    target = get_next_version(current)

    print(f"Cluster: {CLUSTER_NAME}")
    print(f"Current version: {current}")
    print(f"Target version:  {target}")
    print("─" * 50)

    # Validate target version is supported
    if not validate_target_version(target):
        print(f"\n✓ Control plane is already on the latest supported version ({current}).")
        print("  Checking if node groups and add-ons still need updates...\n")

        # Still update add-ons and node groups to match current version
        ensure_nodes_available()

        print("⏳ Updating add-ons...")
        update_addons(current)

        print("\n⏳ Upgrading managed node groups...")
        rolling_upgrade_managed_nodegroups()

        print("\n⏳ Upgrading self-managed node groups...")
        rolling_upgrade_self_managed_nodegroups(current)

        print("\n" + "─" * 50)
        print(f"✓ Cluster fully aligned to {current}")
        print_cluster_status()
        sys.exit(0)

    # Pre-flight: ensure node groups match current version before upgrading control plane
    print("\n⏳ Pre-flight: ensuring node groups match cluster version...")
    if not ensure_nodegroups_match_cluster_version(current):
        print("\n⚠️  Pre-flight failed: not all node groups could be aligned.")
        print("  Resolve node group issues before retrying.")
        sys.exit(1)

    # Pre-flight: ensure at least one node group has nodes for add-on scheduling
    ensure_nodes_available()

    # Step 1: Control plane
    upgrade_control_plane(target)

    # Step 2: Add-ons
    print("\n⏳ Updating add-ons...")
    update_addons(target)

    # Step 3: Data plane — managed node groups
    print("\n⏳ Upgrading managed node groups...")
    rolling_upgrade_managed_nodegroups()

    # Step 4: Data plane — self-managed node groups
    print("\n⏳ Upgrading self-managed node groups...")
    rolling_upgrade_self_managed_nodegroups(target)

    print("\n" + "─" * 50)
    print(f"✓ Cluster fully upgraded to {target}")
    print_cluster_status()


if __name__ == "__main__":
    main()
