variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "cluster_name" {
  type    = string
  default = "k8s-prod-eks"
}

variable "cluster_version" {
  type    = string
  default = "1.32"
}

variable "node_group_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 1
}

variable "eks_addons" {
  type = map(object({
    addon_version            = optional(string)
    resolve_conflicts        = optional(string, "OVERWRITE")
    service_account_role_arn = optional(string)
  }))
  default = {}
}
