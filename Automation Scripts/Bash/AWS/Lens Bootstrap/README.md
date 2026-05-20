# EKS OpenLens Bootstrap — Developer Access + Break-Glass Admin

Automated discovery and kubeconfig setup for EKS clusters, with a tiered access model:
standard developer access for daily work, and a break-glass admin path for incident response.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  NORMAL ACCESS (day-to-day)                                     │
│                                                                 │
│  Role: eks-developer-role                                       │
│  Access: View or Edit (per-cluster tag)                         │
│  Assumption: any engineer with team=engineering tag              │
│  Duration: default (1 hour)                                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  BREAK-GLASS ACCESS (incidents only)                            │
│                                                                 │
│  Role: eks-breakglass-admin                                     │
│  Access: AmazonEKSClusterAdminPolicy on ALL clusters            │
│  Assumption: requires MFA + principal tag breakglass=authorized  │
│  Duration: 1 hour max session                                   │
│  Audit: CloudTrail + SNS alert on every assumption              │
└─────────────────────────────────────────────────────────────────┘
```

## Flow

```
Tag clusters → Terraform discovers tagged clusters → Creates access entries → setup-clusters.sh configures kubeconfig → OpenLens ready
```

---

## Cluster Tagging

Before the developer role can access a cluster, it needs two tags:

| Tag | Purpose |
|---|---|
| `developer-access=true` | Enables discovery by the developer role |
| `developer-access-level=<policy>` | Controls the access level granted |

### Access Levels

| Level | EKS Policy | Description |
|---|---|---|
| `view` | `AmazonEKSViewPolicy` | Read-only access (safe for all engineers) |
| `edit` | `AmazonEKSEditPolicy` | Deploy workloads, manage configmaps/secrets |
| `admin` | `AmazonEKSClusterAdminPolicy` | Full cluster admin (use sparingly) |

### Option A: Script (`tag-clusters.sh`)

Imperative approach — good for ad-hoc tagging or quick onboarding of clusters.

```bash
# See current tagging status across all regions
./tag-clusters.sh list

# Tag all clusters in a region with edit access
./tag-clusters.sh tag --region us-east-1 --level edit

# Tag specific clusters with view access
./tag-clusters.sh tag --clusters my-app-prod,my-app-staging --level view

# Preview changes without applying
./tag-clusters.sh tag --level edit --dry-run

# Remove developer access from a cluster
./tag-clusters.sh untag --clusters my-app-prod
```

### Option B: Terraform (`cluster-tags.tf`)

Declarative approach — good for GitOps workflows where cluster access is defined in code.

Edit `cluster-tags.auto.tfvars`:

```hcl
cluster_access_config = {
  "my-app-prod" = {
    access_level = "view"
  }
  "my-app-staging" = {
    access_level = "edit"
  }
  "my-app-dev" = {
    access_level = "edit"
  }
}
```

Then apply:

```bash
terraform apply
```

Terraform tags the clusters, and the dynamic lookup in `main.tf` automatically creates the corresponding EKS access entries and policy associations.

---

## Kubeconfig Setup

### Normal Mode (daily development)

```bash
./setup-clusters.sh
```

Discovers clusters tagged `developer-access=true` and configures kubeconfig with the standard developer role.

### Break-Glass Mode (incident response)

```bash
./setup-clusters.sh --breakglass
```

Configures ALL clusters with ClusterAdmin access. Requires MFA and `breakglass=authorized` principal tag.

---

## Comparison

| | Normal Mode | Break-Glass Mode |
|---|---|---|
| Command | `./setup-clusters.sh` | `./setup-clusters.sh --breakglass` |
| Role | `eks-developer-role` | `eks-breakglass-admin` |
| Clusters | Only tagged `developer-access=true` | ALL clusters in all regions |
| Access level | Per-cluster tag (View/Edit) | ClusterAdmin everywhere |
| Requires MFA | No | Yes |
| Requires tag | `team=engineering` | `breakglass=authorized` |
| Session duration | Default (1 hour) | Max 1 hour (hard limit) |
| Alerting | None | SNS email to on-call immediately |
| Use case | Daily development | Active incident response |

---

## Security Controls on Break-Glass

- **MFA required** — can't assume the role without active MFA session
- **Explicit tag** — only principals tagged `breakglass=authorized` can assume (small group)
- **1 hour max session** — forces re-authentication for extended incidents
- **Immediate alerting** — EventBridge fires an SNS notification the moment the role is assumed
- **CloudTrail audit** — every assumption and every K8s API call is logged
- **Confirmation prompt** — script requires explicit `y` before proceeding
- **Visual warning** — clear messaging that this is an elevated action

## Revoking Access

| Action | How |
|---|---|
| Remove developer access from a cluster | `./tag-clusters.sh untag --clusters <name>` or remove from `cluster-tags.auto.tfvars` and apply |
| Revoke break-glass for a person | Remove their `breakglass=authorized` principal tag — takes effect immediately |

---

## Terraform Deployment

```bash
terraform init
terraform plan
terraform apply
```

Set the on-call alert email:

```bash
terraform apply -var="breakglass_alert_email=oncall@yourcompany.com"
```

## File Structure

```
├── main.tf                     # Roles, access entries, break-glass alerting
├── cluster-tags.tf             # Declarative cluster tagging resource
├── cluster-tags.auto.tfvars    # Define which clusters get developer access
├── setup-clusters.sh           # Kubeconfig bootstrap for OpenLens
├── tag-clusters.sh             # Imperative cluster tagging script
└── README.md
```

---

## Setup Order & Commands

Run these steps in order. Tagging comes first so Terraform can discover all target clusters during the initial apply.

### Step 1: Tag Clusters for Developer Access

Tag your clusters before deploying infrastructure so Terraform picks them all up on the first apply.

Choose one approach — don't mix both on the same cluster.

**Option A — Script (ad-hoc / quick onboarding):**

```bash
# Check what exists first
./tag-clusters.sh list

# Tag clusters with the desired access level
./tag-clusters.sh tag --clusters my-app-prod --level view
./tag-clusters.sh tag --clusters my-app-staging,my-app-dev --level edit

# Or tag everything in a region
./tag-clusters.sh tag --region us-east-1 --level edit
```

**Option B — Terraform (GitOps / version-controlled):**

Edit `cluster-tags.auto.tfvars`:

```hcl
cluster_access_config = {
  "my-app-prod" = {
    access_level = "view"
  }
  "my-app-staging" = {
    access_level = "edit"
  }
  "my-app-dev" = {
    access_level = "edit"
  }
}
```

> If using Option B, the tags are applied as part of Step 2 below.

---

### Step 2: Deploy Infrastructure

Now that clusters are tagged (or defined in tfvars), Terraform discovers them and provisions everything in one shot.

```bash
terraform init
terraform plan
terraform apply -var="breakglass_alert_email=oncall@yourcompany.com"
```

**What this creates:**
- `eks-developer-role` (day-to-day access)
- `eks-breakglass-admin` (incident response)
- EKS access entries + policy associations for all tagged clusters
- Break-glass ClusterAdmin entries on ALL clusters
- SNS topic + EventBridge rule for break-glass alerts
- Cluster tags (if using Option B)

---

### Step 3: Configure Kubeconfig for OpenLens

Run the bootstrap script to write kubeconfig entries for all accessible clusters.

```bash
# Normal mode — only tagged clusters, standard developer role
./setup-clusters.sh
```

Lens — your clusters are ready.

---

### Step 4 (Incident Only): Break-Glass Access

Only run this during an active incident when you need ClusterAdmin on all clusters.

```bash
./setup-clusters.sh --breakglass
```

After the incident is resolved, revert to normal access:

```bash
./setup-clusters.sh
```

---

### Quick Reference

| Step | When | Command |
|------|------|---------|
| 1A | Tag clusters (ad-hoc) | `./tag-clusters.sh tag --clusters <name> --level <view\|edit\|admin>` |
| 1B | Tag clusters (GitOps) | Edit `cluster-tags.auto.tfvars` |
| 2 | Deploy / update infra | `terraform apply` |
| 3 | Configure kubeconfig | `./setup-clusters.sh` |
| 4 | Incidents only | `./setup-clusters.sh --breakglass` |

---

### Ongoing Maintenance

```bash
# Add a new cluster to developer access
./tag-clusters.sh tag --clusters new-cluster --level edit
terraform apply
./setup-clusters.sh

# Change a cluster's access level
./tag-clusters.sh tag --clusters my-app-prod --level edit
terraform apply
./setup-clusters.sh

# Remove a cluster from developer access
./tag-clusters.sh untag --clusters my-app-prod
terraform apply
./setup-clusters.sh

# Revoke break-glass for a person (immediate, no terraform needed)
aws iam untag-user --user-name <username> --tag-keys breakglass
```
