module "ng_subnets" {
  source = "/Users/dom/Documents/GitHub/DevOpsProjects/EKS Environment/Network Infra/"
}

resource "aws_iam_role" "eks_dev_ng_role_green" {
  name = "${var.clustername}-dev-ng-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_dev_ng_role_green-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_dev_ng_role_green.name
}

resource "aws_iam_role_policy_attachment" "eks_dev_ng_role_green-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_dev_ng_role_green.name
}

resource "aws_iam_role_policy_attachment" "eks_dev_ng_role_green-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_dev_ng_role_green.name
}

resource "aws_eks_node_group" "dev_blue_ng" {
  cluster_name    = var.clustername
  node_group_name = "${var.clustername}-blue-ng"
  node_role_arn   = aws_iam_role.eks_dev_ng_role_green.arn
  subnet_ids = [
    module.subnets.public_subnets["dev-blue"],
    module.subnets.private_subnets["dev-blue"],
  ]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks_dev_ng_role_green-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_dev_ng_role_green-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_dev_ng_role_green-AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_eks_node_group" "dev_green_ng" {
  cluster_name    = var.clustername
  node_group_name = "${var.clustername}-green-ng"
  node_role_arn   = aws_iam_role.eks_dev_ng_role_green.arn
  subnet_ids = [
    module.subnets.public_subnets["dev-green"],
    module.subnets.private_subnets["dev-green"],
  ]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks_dev_ng_role_green-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_dev_ng_role_green-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_dev_ng_role_green-AmazonEC2ContainerRegistryReadOnly,
  ]
}
