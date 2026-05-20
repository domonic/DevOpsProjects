variable "region" {
  type    = string
  default = "us-east-1"
}

variable "access_tag_key" {
  type    = string
  default = "developer-access"
}

variable "access_tag_value" {
  type    = string
  default = "true"
}

variable "default_access_level" {
  type    = string
  default = "AmazonEKSViewPolicy"
}

variable "breakglass_alert_email" {
  type        = string
  description = "Email to notify when break-glass role is assumed"
  default     = "oncall@company.com"
}

data "aws_caller_identity" "current" {}

# ─── Discover all EKS clusters dynamically ────────────────────────────────────

data "aws_eks_clusters" "all" {}

data "aws_eks_cluster" "details" {
  for_each = toset(data.aws_eks_clusters.all.names)
  name     = each.value
}

locals {
  developer_clusters = {
    for name, cluster in data.aws_eks_cluster.details :
    name => {
      cluster      = cluster
      access_level = lookup(cluster.tags, "developer-access-level", var.default_access_level)
    }
    if lookup(cluster.tags, var.access_tag_key, "") == var.access_tag_value
  }

  # Break-glass gets access to ALL clusters, not just tagged ones
  all_clusters = data.aws_eks_clusters.all.names
}

# ═══════════════════════════════════════════════════════════════════════════════
# STANDARD DEVELOPER ROLE (day-to-day access)
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "eks_developer" {
  name = "eks-developer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/team" = "engineering"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eks_describe" {
  name = "eks-describe-clusters"
  role = aws_iam_role.eks_developer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      Resource = "*"
    }]
  })
}

resource "aws_eks_access_entry" "developer" {
  for_each      = local.developer_clusters
  cluster_name  = each.key
  principal_arn = aws_iam_role.eks_developer.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "developer" {
  for_each      = local.developer_clusters
  cluster_name  = each.key
  principal_arn = aws_iam_role.eks_developer.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/${each.value.access_level}"

  access_scope {
    type = "cluster"
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# BREAK-GLASS ADMIN ROLE (incident response only)
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_iam_role" "eks_breakglass" {
  name                 = "eks-breakglass-admin"
  max_session_duration = 3600 # 1 hour max — forces re-auth for extended incidents

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        # Requires MFA to assume
        Bool = {
          "aws:MultiFactorAuthPresent" = "true"
        }
        # Only principals explicitly tagged for break-glass access
        StringEquals = {
          "aws:PrincipalTag/breakglass" = "authorized"
        }
      }
    }]
  })

  tags = {
    purpose     = "incident-response"
    alert       = "true"
    auto-revoke = "true"
  }
}

resource "aws_iam_role_policy" "breakglass_eks" {
  name = "eks-full-access"
  role = aws_iam_role.eks_breakglass.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:*"]
      Resource = "*"
    }]
  })
}

# Break-glass gets ClusterAdmin on ALL clusters (not just tagged ones)
resource "aws_eks_access_entry" "breakglass" {
  for_each      = toset(local.all_clusters)
  cluster_name  = each.value
  principal_arn = aws_iam_role.eks_breakglass.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "breakglass" {
  for_each      = toset(local.all_clusters)
  cluster_name  = each.value
  principal_arn = aws_iam_role.eks_breakglass.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ─── Break-Glass Alerting ─────────────────────────────────────────────────────
# Sends an alert every time the break-glass role is assumed

resource "aws_sns_topic" "breakglass_alerts" {
  name = "eks-breakglass-alerts"
}

resource "aws_sns_topic_subscription" "breakglass_email" {
  topic_arn = aws_sns_topic.breakglass_alerts.arn
  protocol  = "email"
  endpoint  = var.breakglass_alert_email
}

resource "aws_cloudwatch_event_rule" "breakglass_assumed" {
  name        = "eks-breakglass-role-assumed"
  description = "Fires when the break-glass admin role is assumed"

  event_pattern = jsonencode({
    source      = ["aws.sts"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["sts.amazonaws.com"]
      eventName   = ["AssumeRole"]
      requestParameters = {
        roleArn = [aws_iam_role.eks_breakglass.arn]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "breakglass_sns" {
  rule      = aws_cloudwatch_event_rule.breakglass_assumed.name
  target_id = "notify-oncall"
  arn       = aws_sns_topic.breakglass_alerts.arn

  input_transformer {
    input_paths = {
      user = "$.detail.userIdentity.arn"
      time = "$.detail.eventTime"
    }
    input_template = "\"BREAK-GLASS ALERT: EKS admin role assumed by <user> at <time>. Verify this is an authorized incident response action.\""
  }
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.breakglass_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.breakglass_alerts.arn
    }]
  })
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "developer_role_arn" {
  value = aws_iam_role.eks_developer.arn
}

output "breakglass_role_arn" {
  value = aws_iam_role.eks_breakglass.arn
}

output "configured_clusters" {
  value = {
    for name, config in local.developer_clusters :
    name => config.access_level
  }
}

output "breakglass_clusters" {
  value = local.all_clusters
}
