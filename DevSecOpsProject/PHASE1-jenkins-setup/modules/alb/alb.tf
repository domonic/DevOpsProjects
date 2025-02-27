resource "aws_lb" "jenkins" {
  name               = "jenkins-alb"
  internal           = false
  load_balancer_type = "application"

  subnets     = var.subnet_alb_ids
  security_groups = [aws_security_group.jenkins-alb-sg.id]

  tags = {
    Terraform   = "true"
  }
}