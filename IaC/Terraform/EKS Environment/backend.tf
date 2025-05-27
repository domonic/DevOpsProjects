terraform {

  backend "s3" {

    bucket       = "devops-projects-eks-environments-state"
    key          = "EKS/terraform.tfstate"
    region       = "us-west-2"
    use_lockfile = true # This enables native S3 state locking
  }

}


resource "aws_s3_bucket_server_side_encryption_configuration" "backend_encryption" {
  bucket = "devops-projects-eks-environments-state"

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket = "devops-projects-eks-environments-state"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
