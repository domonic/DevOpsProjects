variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string

}
variable "subnet_ids" {
  description = "Subnet IDs to launch the cluster into"
  type        = list(string)
}

variable "node_group_instance_types" {
  description = "List of EC2 instance types for the node group"
  type        = list(string)
}

variable "desired_capacity" {
  description = "Desired number of nodes"
  type        = number
}

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
}



variable "eks_addons" {
  description = "Map of EKS add-ons to install"
  type = map(object({
    addon_version            = optional(string)
    resolve_conflicts        = optional(string, "OVERWRITE")
    service_account_role_arn = optional(string)
  }))
  default = {}
}
