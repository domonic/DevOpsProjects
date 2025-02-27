 resource "aws_eks_node_group" "k8s-blue-worker-node-group" {
  cluster_name  = var.k8s-blue-green
  node_group_name = "k8s-blue-ng"
  node_role_arn  = aws_iam_role.devsecops-workernodes.arn
  subnet_ids   = var.subnet_blue_ids
  instance_types = ["t3.xlarge"]
 
  scaling_config {
   desired_size = 1
   max_size   = 1
   min_size   = 1
  }
 
  depends_on = [
   aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
   aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
   aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
 }