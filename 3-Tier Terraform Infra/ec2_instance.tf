# Using Terraform IaC to deploy 1st EC2 instance in Public Subnet
resource "aws_instance" "devopsinstance1" {
  ami                         = "ami-0b029b1931b347543"
  instance_type               = "t2.micro"
  key_name                    = "devops"
  vpc_security_group_ids      = ["${aws_security_group.devopssg.id}"]
  subnet_id                   = "${aws_subnet.public-subnet-1.id}"
  associate_public_ip_address = true
  user_data                   = "${file("userdata.sh")}"
tags = {
    Name = "DevOps Public Instance 1"
  }
}
# Using Terraform IaC to deploy 2nd EC2 instance in Public Subnet
resource "aws_instance" "devopsinstance2" {
  ami                         = "ami-0b029b1931b347543"
  instance_type               = "t2.micro"
  key_name                    = "devops"
  vpc_security_group_ids      = ["${aws_security_group.devopssg.id}"]
  subnet_id                   = "${aws_subnet.public-subnet-2.id}"
  associate_public_ip_address = true
  user_data                   = "${file("userdata.sh")}"
tags = {
    Name = "DevOps Public Instance 2"
  }
}