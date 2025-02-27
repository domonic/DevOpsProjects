resource "aws_instance" "jenkins-instance" {
  count = 1
  user_data = "${base64encode(file("PHASE1-jenkins-setup/modules/ec2/jenkinsuserdata.sh"))}"
  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = ["${aws_security_group.jenkins-instance-sg.id}"]

  tags = {
    Name = "jenkinsDocker-spare-instance"
  }

  subnet_id = "${var.subnet}"
}



resource "aws_instance" "monitoring-instance" {
  count = 1

  ami           = var.ami_id
  instance_type = var.instance_type
  vpc_security_group_ids = ["${aws_security_group.monitoring-instance-sg.id}"]

  tags = {
    Name = "monitoring-instance"
  }

  subnet_id = "${var.subnet}"
}



