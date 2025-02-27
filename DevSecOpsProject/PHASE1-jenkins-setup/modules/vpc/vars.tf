# Defining CIDR Block for VPC
variable "vpc_cidr" {
  default = "172.31.0.0/16"
}


# Defining CIDR Blocks for VPC Subnets
variable "k8s-blue-2a_cidr" {
  default = "172.31.160.0/21"
}

variable "k8s-blue-2b_cidr" {
  default = "172.31.168.0/21"
}

variable "k8s-blue-2c_cidr" {
  default = "172.31.176.0/21"
}

variable "k8s-green-2a_cidr" {
  default = "172.31.184.0/21"
}

variable "k8s-green-2b_cidr" {
  default = "172.31.208.0/21"
}

variable "k8s-green-2c_cidr" {
  default = "172.31.216.0/21"
}


