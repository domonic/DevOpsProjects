variable "name" {}

variable "performance_mode" {
  default = "generalPurpose"
}

variable "throughput_mode" {
  default = "bursting"
}

variable "encrypted" {
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "subnet_ids" {
  type = list(string)
}

variable "vpc_id" {}

variable "vpc_cidr_block" {}
