resource "aws_efs_file_system" "jenkins" {
  creation_token = "jenkins"
  encrypted      = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  tags = {
    Name = "jenkins-efs"
  }
}

resource "aws_efs_mount_target" "jenkins" {
  file_system_id   = aws_efs_file_system.jenkins.id
  subnet_id        = "${var.subnet}"
  security_groups = ["${var.jenkins-efs-sg}"]
}