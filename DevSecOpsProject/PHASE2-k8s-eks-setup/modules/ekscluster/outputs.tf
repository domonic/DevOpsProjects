output "k8s-blue-green" {
    value = aws_eks_cluster.k8s-blue-green.name
}


output "k8s-blue-green-oidc-url" {
    value = aws_eks_cluster.k8s-blue-green.identity[0].oidc[0].issuer
}