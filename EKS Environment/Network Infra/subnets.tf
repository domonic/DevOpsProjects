resource "aws_subnet" "public" {
  for_each = merge([
    for env, groups in var.public_subnets : {
      for group, subnets in groups :
      "${env}-${group}" => { subnet_list = subnets }
    }
  ]...)

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.subnet_list[0] # First CIDR block in the list
  availability_zone = var.azs[index(var.public_subnets[split("-", each.key)[0]][split("-", each.key)[1]], each.value.subnet_list[0])]

  map_public_ip_on_launch = true

  tags = {
    Name            = "public-${each.key}"
    Environment     = split("-", each.key)[0] # Extracts 'dev', 'staging', 'prod'
    DeploymentGroup = split("-", each.key)[1] # Extracts 'blue', 'green'
  }
}

resource "aws_subnet" "private" {
  for_each = merge([
    for env, groups in var.private_subnets : {
      for group, subnets in groups :
      "${env}-${group}" => { subnet_list = subnets }
    }
  ]...)

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.subnet_list[0] # First CIDR block in the list
  availability_zone = var.azs[index(var.private_subnets[split("-", each.key)[0]][split("-", each.key)[1]], each.value.subnet_list[0])]


  tags = {
    Name            = "private-${each.key}"
    Environment     = split("-", each.key)[0] # Extracts 'dev', 'staging', 'prod'
    DeploymentGroup = split("-", each.key)[1] # Extracts 'blue', 'green'
  }
}
