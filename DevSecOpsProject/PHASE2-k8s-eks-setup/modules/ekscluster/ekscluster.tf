resource "aws_eks_cluster" "k8s-blue-green" {
 name = "k8s-blue-green"
 role_arn = var.devsecops-eks-iam-role-arn

 vpc_config {
  subnet_ids = var.subnet_ids

 }

 depends_on = [
  var.devsecops-eks-iam-role,
 ]
}