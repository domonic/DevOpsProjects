# Using Terraform IaC to deploy VPC Resource Into AWS
resource "aws_vpc" "devopsprojectsvpc" {
  cidr_block       = "${var.vpc_cidr}"
  instance_tenancy = "default" 
  tags = {
    Name = "DevOps Projects VPC"
  }
}

