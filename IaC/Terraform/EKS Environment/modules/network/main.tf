
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
locals {
  public_subnets_nested = flatten([
    for env in var.envs : [
      for deployment in var.deployments : [
        for idx, az in var.azs : {
          key        = "${env}-${deployment}-${az}"
          cidr_block = var.public_subnets[env][deployment][idx]
          az         = az
          env        = env
          group      = deployment
        }
      ]
    ]
  ])

  public_subnets_map = {
    for item in local.public_subnets_nested :
    item.key => {
      cidr_block = item.cidr_block
      az         = item.az
      env        = item.env
      group      = item.group
    }
  }

  private_subnets_nested = flatten([
    for env in var.envs : [
      for deployment in var.deployments : [
        for idx, az in var.azs : {
          key        = "${env}-${deployment}-${az}"
          cidr_block = var.private_subnets[env][deployment][idx]
          az         = az
          env        = env
          group      = deployment
        }
      ]
    ]
  ])

  private_subnets_map = {
    for item in local.private_subnets_nested :
    item.key => {
      cidr_block = item.cidr_block
      az         = item.az
      env        = item.env
      group      = item.group
    }
  }
}


resource "aws_subnet" "public" {
  for_each = local.public_subnets_map

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name                                              = "public-${each.value.env}-${each.value.group}-${each.value.az}"
    Environment                                       = each.value.env
    DeploymentGroup                                   = each.value.group
    "kubernetes.io/role/elb"                          = "1"
    "kubernetes.io/cluster/k8s-${each.value.env}-eks" = "owned"
  }
}



# private subnet infra
resource "aws_subnet" "private" {
  for_each = local.private_subnets_map

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az


  tags = {
    Name                                              = "private-${each.value.env}-${each.value.group}-${each.value.az}"
    Environment                                       = each.value.env
    DeploymentGroup                                   = each.value.group
    "kubernetes.io/role/internal-elb"                 = "1"
    "kubernetes.io/cluster/k8s-${each.value.env}-eks" = "owned"
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
  subnet_id     = aws_subnet.public["prod-green-us-west-2a"].id


  tags = {
    Name = "EKS Env NATGW"
  }
}
