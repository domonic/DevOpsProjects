# Using Terraform IaC to deploy VPC Resource Into AWS
resource "aws_vpc" "devsecopsvpc" {
  cidr_block       = "${var.vpc_cidr}"
  instance_tenancy = "default" 
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "DevSecOps-Project-VPC"
  }
}


