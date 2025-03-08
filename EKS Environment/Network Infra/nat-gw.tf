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
