resource "aws_efs_file_system" "this" {
  creation_token   = var.name
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode
  encrypted        = var.encrypted
  tags             = var.tags
}

data "aws_subnet" "efs_subnets" {
  for_each = toset(var.subnet_ids)
  id       = each.key
}

locals {
  # Group all subnet IDs by AZ
  grouped_subnets = {
    for subnet_id, subnet in data.aws_subnet.efs_subnets :
    subnet.availability_zone => subnet_id...
  }

  # Pick the first subnet ID in each AZ group
  az_to_subnet = {
    for az, subnet_ids in local.grouped_subnets :
    az => subnet_ids[0]
  }
}

resource "aws_efs_mount_target" "this" {
  for_each = local.az_to_subnet

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.this.id]
}


resource "aws_security_group" "this" {
  name        = "${var.name}-efs-sg"
  description = "Allow NFS traffic for EFS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_access_point" "this" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/${var.name}"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }
}

output "file_system_id" {
  value = aws_efs_file_system.this.id
}

output "access_point_id" {
  value = aws_efs_access_point.this.id
}

output "security_group_id" {
  value = aws_security_group.this.id
}

