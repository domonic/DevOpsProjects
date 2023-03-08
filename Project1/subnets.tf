# Using Terraform IaC to deploy VPC 1st Web Subnet Into AWS 
resource "aws_subnet" "public-subnet-1" {
  vpc_id                  = "${aws_vpc.devopsprojectsvpc.id}"
  cidr_block             = "${var.subnet1_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-west-2a"
tags = {
    Name = "Web Subnet 1"
  }
}
# Using Terraform IaC to deploy VPC 2nd Web Subnet Into AWS 
resource "aws_subnet" "public-subnet-2" {
  vpc_id                  = "${aws_vpc.devopsprojectsvpc.id}"
  cidr_block             = "${var.subnet2_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-west-2b"
tags = {
    Name = "Web Subnet 2"
  }
}
# Using Terraform IaC to deploy VPC 1st Application Subnet Into AWS  
resource "aws_subnet" "application-subnet-1" {
  vpc_id                  = "${aws_vpc.devopsprojectsvpc.id}"
  cidr_block             = "${var.subnet3_cidr}"
  map_public_ip_on_launch = false
  availability_zone = "us-west-2a"
tags = {
    Name = "Application Subnet 1"
  }
}
# Using Terraform IaC to deploy VPC 2nd Application Subnet Into AWS  
resource "aws_subnet" "application-subnet-2" {
  vpc_id                  = "${aws_vpc.devopsprojectsvpc.id}"
  cidr_block             = "${var.subnet4_cidr}"
  map_public_ip_on_launch = false
  availability_zone = "us-west-2b"
tags = {
    Name = "Application Subnet 2"
  }
}
# Using Terraform IaC to deploy VPC 1st Database Private Subnet Into AWS 
resource "aws_subnet" "database-subnet-1" {
  vpc_id            = "${aws_vpc.devopsprojectsvpc.id}"
  cidr_block        = "${var.subnet5_cidr}"
  availability_zone = "us-west-2a"
tags = {
    Name = "Database Subnet 1"
  }
}
# Using Terraform IaC to deploy VPC 2nd Database Private Subnet Into AWS 
resource "aws_subnet" "database-subnet-2" {
  vpc_id            = "${aws_vpc.devopsprojectsvpc.id}"
  cidr_block        = "${var.subnet6_cidr}"
  availability_zone = "us-west-2b"
tags = {
    Name = "Database Subnet 2"
  }
}