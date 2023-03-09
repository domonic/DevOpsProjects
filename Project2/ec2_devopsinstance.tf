# Using Terraform IaC to deploy EC2 instance For Jenkins in Public Subnet
resource "aws_instance" "jenkinsinstance1" {
  ami                         = "ami-0b029b1931b347543"
  instance_type               = "t2.medium"
  key_name                    = "devops"
  vpc_security_group_ids      = ["${aws_security_group.devopssg.id}"]
  subnet_id                   = "${aws_subnet.public-subnet-1.id}"
  associate_public_ip_address = true
  user_data                   = "${file("jenkinsuserdata.sh")}"
tags = {
    Name = "Jenkins Public Instance 1"
  }
}

# Using Terraform IaC to deploy EC2 instance For Ansible in Public Subnet
resource "aws_instance" "ansibleinstance1" {
  ami                         = "ami-0b029b1931b347543"
  instance_type               = "t2.medium"
  key_name                    = "devops"
  vpc_security_group_ids      = ["${aws_security_group.devopssg.id}"]
  subnet_id                   = "${aws_subnet.public-subnet-1.id}"
  associate_public_ip_address = true
  user_data                   = "${file("ansibleuserdata.sh")}"
tags = {
    Name = "Ansible Public Instance 2"
  }
}