variable "vpc_id" {}

variable "subnet_alb_ids" {
  
}


variable "jenkins-efs-sg"{

}


variable "ami_id" {
  type = string
  default = "ami-0f5daaa3a7fb3378b"
}

variable "instance_type" {
  type = string
  default = "t3.large"
}

variable "jenkins-instance-sg"{

}
