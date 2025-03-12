module "subnets" {
  source = "/Users/dom/Documents/GitHub/DevOpsProjects/EKS Environment/Network Infra/"
}

resource "aws_eks_cluster" "eks-dev-green" {
  name = "eks-dev-green"

  access_config {
    authentication_mode = "API"
  }

  role_arn = aws_iam_role.cluster.arn
  version  = 1.32

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids = [
      module.subnets.public_subnets["dev-blue"],
      module.subnets.private_subnets["dev-blue"],
      module.subnets.public_subnets["dev-green"],
      module.subnets.private_subnets["dev-green"],

    ]
  }

  # Ensure that IAM Role permissions are created before and deleted
  # after EKS Cluster handling. Otherwise, EKS will not be able to
  # properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    #aws_iam_role_policy_attachment.cluster_AmazonEKSComputePolicy,
    #aws_iam_role_policy_attachment.cluster_AmazonEKSBlockStoragePolicy,
    #aws_iam_role_policy_attachment.cluster_AmazonEKSLoadBalancingPolicy,
    #aws_iam_role_policy_attachment.cluster_AmazonEKSNetworkingPolicy,
    module.subnets.public_subnets,
    module.subnets.private_subnets,
    module.subnets.aws_nat_gateway,


  ]
}

resource "aws_iam_role" "cluster" {
  name = "eks-dev-green"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSComputePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSBlockStoragePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSLoadBalancingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSNetworkingPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
  role       = aws_iam_role.cluster.name
}
