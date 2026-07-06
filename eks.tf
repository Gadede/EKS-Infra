module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.35"

  # Lets you run kubectl from your laptop (public endpoint), while node-to-control-plane
  # traffic still goes over the private network. Fine for learning; a production
  # setup would usually restrict this to specific IP ranges or disable it entirely.
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # This makes the IAM user/role that runs `terraform apply` a cluster admin
  # automatically - otherwise you'd create a cluster you can't even kubectl into.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      name           = "${var.cluster_name}-ng"
      instance_types = ["t3.micro"]

      min_size     = 1
      max_size     = 2
      desired_size = 2
    }
  }

  tags = {
    Project = var.project_name
  }
}
