#  Using Terraform IaC to deploy Internet Gateway and attach to VPC Into AWS 
resource "aws_internet_gateway" "devsecopsigw" {
  vpc_id = "${aws_vpc.devsecopsvpc.id}"

  tags = {
        Name = "devsecopsigw"
    }
}