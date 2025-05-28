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
      blue  = ["10.0.0.0/23", "10.0.2.0/23", "10.0.4.0/23", "10.0.6.0/23", "10.0.8.0/23", "10.0.10.0/23"]
      green = ["10.0.12.0/23", "10.0.14.0/23", "10.0.16.0/23", "10.0.18.0/23", "10.0.20.0/23", "10.0.22.0/23"]
    }
    dev = {
      blue  = ["10.0.24.0/23", "10.0.26.0/23", "10.0.28.0/23", "10.0.30.0/23", "10.0.32.0/23", "10.0.34.0/23"]
      green = ["10.0.36.0/23", "10.0.38.0/23", "10.0.40.0/23", "10.0.42.0/23", "10.0.44.0/23", "10.0.46.0/23"]
    }
    prod = {
      blue  = ["10.0.48.0/23", "10.0.50.0/23", "10.0.52.0/23", "10.0.54.0/23", "10.0.56.0/23", "10.0.58.0/23"]
      green = ["10.0.60.0/23", "10.0.62.0/23", "10.0.64.0/23", "10.0.66.0/23", "10.0.68.0/23", "10.0.70.0/23"]
    }
  }
}

variable "private_subnets" {
  description = "Private subnets mapped to environments and deployments"
  type        = map(map(list(string)))
  default = {
    staging = {
      blue  = ["10.0.72.0/23", "10.0.74.0/23", "10.0.76.0/23", "10.0.78.0/23", "10.0.80.0/23", "10.0.82.0/23"]
      green = ["10.0.84.0/23", "10.0.86.0/23", "10.0.88.0/23", "10.0.90.0/23", "10.0.92.0/23", "10.0.94.0/23"]
    }
    dev = {
      blue  = ["10.0.96.0/23", "10.0.98.0/23", "10.0.100.0/23", "10.0.102.0/23", "10.0.104.0/23", "10.0.106.0/23"]
      green = ["10.0.108.0/23", "10.0.110.0/23", "10.0.112.0/23", "10.0.114.0/23", "10.0.116.0/23", "10.0.118.0/23"]
    }
    prod = {
      blue  = ["10.0.120.0/23", "10.0.122.0/23", "10.0.124.0/23", "10.0.126.0/23", "10.0.128.0/23", "10.0.130.0/23"]
      green = ["10.0.132.0/23", "10.0.134.0/23", "10.0.136.0/23", "10.0.138.0/23", "10.0.140.0/23", "10.0.142.0/23"]
    }
  }
}
