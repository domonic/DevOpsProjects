#  Using Terraform IaC to deploy Internet Gateway and attach to VPC Into AWS 
resource "aws_internet_gateway" "devopsgateway" {
  vpc_id = "${aws_vpc.devopsprojectsvpc.id}"
}