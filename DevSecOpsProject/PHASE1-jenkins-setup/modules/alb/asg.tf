resource "aws_launch_template" "jenkins" {
  name_prefix   = "jenkins-controller-lt"
  image_id      = var.ami_id
  instance_type = var.instance_type
  user_data = "${base64encode(file("PHASE1-jenkins-setup/modules/alb/jenkinsuserdata.sh"))}"
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = ["${var.jenkins-instance-sg}"]
  }
}

resource "aws_autoscaling_group" "jenkins" {
  name                = "jenkins-controller-asg"
  max_size            = 1
  min_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = var.subnet_alb_ids
  
  launch_template {
    id      = aws_launch_template.jenkins.id
    version = aws_launch_template.jenkins.latest_version
  }

  tag {
    key                 = "Name"
    value               = "jenkins-controller"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [load_balancers, target_group_arns]
  }

  # instance_refresh {
  #   strategy = "Rolling"
  #   triggers = ["launch_template"]
  # }
}


resource "aws_autoscaling_attachment" "jenkins" {
  autoscaling_group_name = aws_autoscaling_group.jenkins.name
  lb_target_group_arn    = aws_lb_target_group.jenkins.arn
}