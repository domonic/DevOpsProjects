# Using Terraform IaC to deploy External LoadBalancer
resource "aws_lb" "external-alb" {
  name               = "external-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.devopssg.id]
  subnets            = [aws_subnet.public-subnet-1.id, aws_subnet.public-subnet-2.id]
}
resource "aws_lb_target_group" "targetgroup-alb" {
  name     = "targetgroup-alb"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.devopsprojectsvpc.id
}
resource "aws_lb_target_group_attachment" "attachment1" {
  target_group_arn = aws_lb_target_group.targetgroup-alb.arn
  target_id        = aws_instance.devopsinstance1.id
  port             = 80
depends_on = [
    aws_instance.devopsinstance1,
  ]
}
resource "aws_lb_target_group_attachment" "attachment2" {
  target_group_arn = aws_lb_target_group.targetgroup-alb.arn
  target_id        = aws_instance.devopsinstance2.id
  port             = 80
depends_on = [
    aws_instance.devopsinstance2,
  ]
}
resource "aws_lb_listener" "external-alb" {
  load_balancer_arn = aws_lb.external-alb.arn
  port              = "80"
  protocol          = "HTTP"
default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.targetgroup-alb.arn
  }
}