module "vpc"{
    source = "./PHASE1-jenkins-setup/modules/vpc"

}


module "ec2" {
    source = "./PHASE1-jenkins-setup/modules/ec2"
    subnet = module.vpc.k8s-blue-2a
    vpc_id = module.vpc.devsecopsvpc
}


module "efs"{
    source = "./PHASE1-jenkins-setup/modules/efs"
    subnet = module.vpc.k8s-blue-2a
    jenkins-efs-sg = module.ec2.jenkins-efs-sg
    vpc_id = module.vpc.devsecopsvpc
}

module "alb" {
    source = "./PHASE1-jenkins-setup/modules/alb"
    jenkins-instance-sg = module.ec2.jenkins-instance-sg
    jenkins-efs-sg = module.ec2.jenkins-efs-sg
    subnet_alb_ids = module.vpc.subnet_alb_ids
    vpc_id = module.vpc.devsecopsvpc
}

module "ecr"{
    source = "./PHASE1-jenkins-setup/modules/ecr"
}


module "iam" {
    source = "./PHASE2-k8s-eks-setup/modules/iam"
}

module "eks" {
    source = "./PHASE2-k8s-eks-setup/modules/ekscluster"
    subnet_ids = module.vpc.subnet_ids
    vpc_id = module.vpc.devsecopsvpc
    devsecops-eks-iam-role = module.iam.devsecops-eks-iam-role
    devsecops-eks-iam-role-arn = module.iam.devsecops-eks-iam-role-arn
}

module "nodegroups" {
    source = "./PHASE2-k8s-eks-setup/modules/nodegroups"
    subnet_green_ids = module.vpc.subnet_green_ids
    subnet_blue_ids = module.vpc.subnet_blue_ids
    vpc_id = module.vpc.devsecopsvpc
    k8s-blue-green = module.eks.k8s-blue-green

  
}

module "eksaddons" {
    source = "./PHASE2-k8s-eks-setup/modules/eksaddons"
    k8s-blue-green = module.eks.k8s-blue-green
}