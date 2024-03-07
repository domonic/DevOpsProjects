# Using Terraform IaC to deploy VPC Subnet Into AWS 
resource "aws_subnet" "k8s-blue-2a" {
  vpc_id                  = "${aws_vpc.devsecopsvpc.id}"
  cidr_block             = "${var.k8s-blue-2a_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-east-2a"
tags = {
    Name = "k8s-blue-2a"
  }
}

# Using Terraform IaC to deploy VPC Subnet Into AWS 
resource "aws_subnet" "k8s-blue-2b" {
  vpc_id                  = "${aws_vpc.devsecopsvpc.id}"
  cidr_block             = "${var.k8s-blue-2b_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-east-2b"
tags = {
    Name = "k8s-blue-2b"
  }
}

# Using Terraform IaC to deploy VPC Subnet Into AWS 
resource "aws_subnet" "k8s-blue-2c" {
  vpc_id                  = "${aws_vpc.devsecopsvpc.id}"
  cidr_block             = "${var.k8s-blue-2c_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-east-2c"
tags = {
    Name = "k8s-blue-2c"
  }
}

# Using Terraform IaC to deploy VPC Subnet Into AWS 
resource "aws_subnet" "k8s-green-2a" {
  vpc_id                  = "${aws_vpc.devsecopsvpc.id}"
  cidr_block             = "${var.k8s-green-2a_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-east-2a"
tags = {
    Name = "k8s-green-2a"
  }
}

# Using Terraform IaC to deploy VPC Subnet Into AWS 
resource "aws_subnet" "k8s-green-2b" {
  vpc_id                  = "${aws_vpc.devsecopsvpc.id}"
  cidr_block             = "${var.k8s-green-2b_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-east-2b"
tags = {
    Name = "k8s-green-2b"
  }
}

# Using Terraform IaC to deploy VPC Subnet Into AWS 
resource "aws_subnet" "k8s-green-2c" {
  vpc_id                  = "${aws_vpc.devsecopsvpc.id}"
  cidr_block             = "${var.k8s-green-2c_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "us-east-2c"
tags = {
    Name = "k8s-green-2c"
  }
}

