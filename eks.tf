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

  # Disabled in favor of an explicit, static access entry below - this flag
  # grants admin to whichever identity happens to run `terraform apply` at
  # that moment, which silently moved from the human operator to the
  # GitHub Actions role once the pipeline started running applies too.
  enable_cluster_creator_admin_permissions = false

  eks_managed_node_groups = {
    default = {
      name           = "${var.cluster_name}-ng"
      instance_types = ["t3.micro"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }
  }

  tags = {
    Project = var.project_name
  }
}
