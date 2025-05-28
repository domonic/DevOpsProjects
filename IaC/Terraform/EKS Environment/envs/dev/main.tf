module "network" {
  source = "../../modules/network"

}

module "eks" {
  source = "../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.network.vpc_id
  subnet_ids = [
    module.network.public_subnets["dev-blue-us-west-2a"],
    module.network.public_subnets["dev-blue-us-west-2b"],
    module.network.public_subnets["dev-blue-us-west-2c"],
    module.network.public_subnets["dev-green-us-west-2a"],
    module.network.public_subnets["dev-green-us-west-2b"],
    module.network.public_subnets["dev-green-us-west-2c"],
    module.network.private_subnets["dev-blue-us-west-2a"],
    module.network.private_subnets["dev-blue-us-west-2b"],
    module.network.private_subnets["dev-blue-us-west-2c"],
    module.network.private_subnets["dev-green-us-west-2a"],
    module.network.private_subnets["dev-green-us-west-2b"],
    module.network.private_subnets["dev-green-us-west-2c"],
  ]
  node_group_instance_types = var.node_group_instance_types
  desired_capacity          = var.desired_capacity
  min_size                  = var.min_size
  max_size                  = var.max_size
  eks_addons                = var.eks_addons
}

module "efs" {
  source = "../../modules/efs"
  name   = "jenkins-efs"
  subnet_ids = [
    module.network.private_subnets["dev-blue-us-west-2a"],
    module.network.private_subnets["dev-blue-us-west-2b"],
    module.network.private_subnets["dev-blue-us-west-2c"],
    module.network.private_subnets["dev-green-us-west-2a"],
    module.network.private_subnets["dev-green-us-west-2b"],
    module.network.private_subnets["dev-green-us-west-2c"],
  ]
  vpc_id         = module.network.vpc_id
  vpc_cidr_block = module.network.cidr_block
  tags = {
    Name = "jenkins-efs"
  }
}


