output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = { for key, value in aws_subnet.public : key => value.id }
}

output "private_subnets" {
  value = { for key, value in aws_subnet.private : key => value.id }
}

output "cidr_block" {
  value = aws_vpc.main.cidr_block
}
