terraform {

  backend "s3" {

    bucket       = "devops-projects-eks-environments-state"
    key          = "EKS/terraform.tfstate"
    region       = "us-west-2"
    use_lockfile = true # This enables native S3 state locking
  }

}
