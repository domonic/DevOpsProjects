# cluster-tags.tf — Declaratively tag EKS clusters for developer access
#
# Define which clusters get developer access and at what level.
# After applying, the main.tf dynamic lookup will pick them up automatically.

variable "cluster_access_config" {
  type = map(object({
    access_level = string # view, edit, or admin
  }))
  description = "Map of cluster names to their developer access configuration"
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.cluster_access_config :
      contains(["view", "edit", "admin"], v.access_level)
    ])
    error_message = "access_level must be one of: view, edit, admin"
  }
}

locals {
  # Resolve friendly names to EKS policy names
  access_level_map = {
    view  = "AmazonEKSViewPolicy"
    edit  = "AmazonEKSEditPolicy"
    admin = "AmazonEKSClusterAdminPolicy"
  }

  # Only tag clusters that actually exist
  taggable_clusters = {
    for name, config in var.cluster_access_config :
    name => config
    if contains(data.aws_eks_clusters.all.names, name)
  }
}

resource "aws_eks_cluster_tags" "developer_access" {
  for_each = local.taggable_clusters

  cluster_name = each.key

  tags = {
    "developer-access"       = "true"
    "developer-access-level" = local.access_level_map[each.value.access_level]
  }
}
