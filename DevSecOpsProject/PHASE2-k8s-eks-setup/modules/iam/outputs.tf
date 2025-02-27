output "devsecops-eks-iam-role" {
  value = aws_iam_role.devsecops-eks-iam-role.name
}

output "devsecops-eks-iam-role-arn" {
  value = aws_iam_role.devsecops-eks-iam-role.arn
}