# Using Terraform IaC to deploy VPC Public Subnet Into AWS 
resource "aws_subnet" "public-subnet-1" {
  vpc_id                  = "${aws_vpc.devopsprojectsvpc.id}"
  cidr_block             = "${var.subnet1_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-west-2a"
tags = {
    Name = "Public Subnet 1"
  }
}

# Using Terraform IaC to deploy VPC Private Subnet Into AWS 
resource "aws_subnet" "private-subnet-1" {
  vpc_id            = "${aws_vpc.devopsprojectsvpc.id}"
  cidr_block        = "${var.subnet2_cidr}"
  availability_zone = "us-west-2a"
tags = {
    Name = "Private Subnet 1"
  }
}