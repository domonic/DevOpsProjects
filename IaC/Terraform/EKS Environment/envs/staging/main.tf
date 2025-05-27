module "network" {
  source = "../../modules/network"

}

module "eks" {
  source = "../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.network.vpc_id
  subnet_ids = [
    module.network.public_subnets["staging-blue"],
    module.network.private_subnets["staging-blue"],
    module.network.public_subnets["staging-green"],
    module.network.private_subnets["staging-green"],
  ]
  node_group_instance_types = var.node_group_instance_types
  desired_capacity          = var.desired_capacity
  min_size                  = var.min_size
  max_size                  = var.max_size

  eks_addons = var.eks_addons
}


