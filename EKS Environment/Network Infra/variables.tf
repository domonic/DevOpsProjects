variable "region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR Block"
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "envs" {
  description = "Environments"
  type        = list(string)
  default     = ["staging", "dev", "prod"]
}

variable "deployments" {
  description = "Deployment groups"
  type        = list(string)
  default     = ["blue", "green"]
}

variable "public_subnets" {
  description = "Public subnets mapped to environments and deployments"
  type        = map(map(list(string)))
  default = {
    staging = {
      blue  = ["10.0.4.0/22", "10.0.8.0/22", "10.0.12.0/22"]
      green = ["10.0.16.0/22", "10.0.20.0/22", "10.0.24.0/22"]
    }
    dev = {
      blue  = ["10.0.28.0/22", "10.0.32.0/22", "10.0.36.0/22"]
      green = ["10.0.40.0/22", "10.0.44.0/22", "10.0.48.0/22"]
    }
    prod = {
      blue  = ["10.0.52.0/22", "10.0.56.0/22", "10.0.60.0/22"]
      green = ["10.0.64.0/22", "10.0.68.0/242", "10.0.72.0/22"]
    }
  }
}

variable "private_subnets" {
  description = "Private subnets mapped to environments and deployments"
  type        = map(map(list(string)))
  default = {
    staging = {
      blue  = ["10.0.80.0/22", "10.0.84.0/22", "10.0.88.0/22"]
      green = ["10.0.92.0/22", "10.0.96.0/22", "10.0.100.0/22"]
    }
    dev = {
      blue  = ["10.0.104.0/22", "10.0.108.0/22", "10.0.112.0/22"]
      green = ["10.0.116.0/22", "10.0.120.0/22", "10.0.124.0/22"]
    }
    prod = {
      blue  = ["10.0.128.0/22", "10.0.132.0/22", "10.0.136.0/22"]
      green = ["10.0.140.0/22", "10.0.144.0/242", "10.0.148.0/22"]
    }
  }
}
