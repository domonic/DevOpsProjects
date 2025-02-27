resource "aws_eks_addon" "coredns" {
  cluster_name  = var.k8s-blue-green
  addon_name                  = "coredns"
  addon_version               = "v1.11.1-eksbuild.6" 
  resolve_conflicts_on_update = "OVERWRITE"
}


resource "aws_eks_addon" "kube-proxy" {
  cluster_name  = var.k8s-blue-green
  addon_name                  = "kube-proxy"
  addon_version               = "v1.29.1-eksbuild.2" 
  resolve_conflicts_on_update = "OVERWRITE"
}


resource "aws_eks_addon" "vpc-cni" {
  cluster_name  = var.k8s-blue-green
  addon_name                  = "vpc-cni"
  addon_version               = "v1.16.2-eksbuild.1" 
  resolve_conflicts_on_update = "OVERWRITE"
}


resource "aws_eks_addon" "aws-ebs-csi-driver" {
  cluster_name  = var.k8s-blue-green
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.28.0-eksbuild.1" 
  resolve_conflicts_on_update = "OVERWRITE"
}



resource "aws_eks_addon" "aws-efs-csi-driver" {
  cluster_name  = var.k8s-blue-green
  addon_name                  = "aws-efs-csi-driver"
  addon_version               = "v1.7.5-eksbuild.2" 
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "snapshot-controller" {
  cluster_name  = var.k8s-blue-green
  addon_name                  = "snapshot-controller"
  addon_version               = "v6.3.2-eksbuild.1" 
  resolve_conflicts_on_update = "OVERWRITE"
}


resource "aws_eks_addon" "amazon-cloudwatch-observability" {
  cluster_name  = var.k8s-blue-green
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = "v1.2.2-eksbuild.1" 
  resolve_conflicts_on_update = "OVERWRITE"
}


