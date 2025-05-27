
# vpc infra
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "EKS Environmnet VPC"
  }
}

# public subnet infra
resource "aws_subnet" "public" {
  for_each = merge([
    for env, groups in var.public_subnets : {
      for group, subnets in groups :
      "${env}-${group}" => { subnet_list = subnets }
    }
  ]...)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.subnet_list[0] # First CIDR block in the list
  availability_zone       = var.azs[index(["blue", "green"], split("-", each.key)[1])]
  map_public_ip_on_launch = true

  tags = {
    Name            = "public-${each.key}"
    Environment     = split("-", each.key)[0] # Extracts 'dev', 'staging', 'prod'
    DeploymentGroup = split("-", each.key)[1] # Extracts 'blue', 'green'
  }
}

# private subnet infra
resource "aws_subnet" "private" {
  for_each = merge([
    for env, groups in var.private_subnets : {
      for group, subnets in groups :
      "${env}-${group}" => { subnet_list = subnets }
    }
  ]...)

  vpc_id     = aws_vpc.main.id
  cidr_block = each.value.subnet_list[0] # First CIDR block in the list
  #availability_zone = var.azs[index(var.private_subnets[split("-", each.key)[0]][split("-", each.key)[1]], each.value.subnet_list[0])]
  availability_zone = var.azs[index(["blue", "green"], split("-", each.key)[1])]
  tags = {
    Name            = "private-${each.key}"
    Environment     = split("-", each.key)[0] # Extracts 'dev', 'staging', 'prod'
    DeploymentGroup = split("-", each.key)[1] # Extracts 'blue', 'green'
  }
}

# public route table infra
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "EKS-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# private route table infra
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "EKS-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# igw infra
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = " EKS Env IGW"
  }
}

# ngw infra
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["prod-green"].id


  tags = {
    Name = "EKS Env NATGW"
  }
}
