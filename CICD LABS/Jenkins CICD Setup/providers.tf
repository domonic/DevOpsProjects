terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

#configure the AWS Provider
provider "aws" {
  profile = "default"
}