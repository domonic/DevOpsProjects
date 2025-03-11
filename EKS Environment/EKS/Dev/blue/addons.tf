resource "aws_eks_addon" "coredns" {
  cluster_name                = var.clustername
  addon_name                  = "coredns"
  addon_version               = "v1.11.4-eksbuild.2" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
}


resource "aws_eks_addon" "kube-proxy" {
  cluster_name                = var.clustername
  addon_name                  = "kube-proxy"
  addon_version               = "v1.32.0-eksbuild.2" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
}


resource "aws_eks_addon" "vpc-cni" {
  cluster_name                = var.clustername
  addon_name                  = "vpc-cni"
  addon_version               = "v1.19.3-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "aws-ebs-csi-driver" {
  cluster_name                = var.clustername
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.40.0-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "aws-efs-csi-driver" {
  cluster_name                = var.clustername
  addon_name                  = "aws-efs-csi-driver"
  addon_version               = "v2.1.6-eksbuild.1" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
}


resource "aws_eks_addon" "metrics-server" {
  cluster_name                = var.clustername
  addon_name                  = "metrics-server"
  addon_version               = "v0.7.2-eksbuild.2" #e.g., previous version v1.9.3-eksbuild.3 and the new version is v1.10.1-eksbuild.1
  resolve_conflicts_on_update = "OVERWRITE"
}
