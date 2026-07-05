data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  # Use the first 2 AZs in the region for high availability
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Private subnets: worker nodes live here, not directly internet-facing
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  # Public subnets: load balancers (like the ALB in Phase 6) live here
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true   # lets private subnet nodes reach the internet (pull images, etc.)
  single_nat_gateway   = true   # one NAT gateway instead of one per AZ, to keep cost down for learning
  enable_dns_hostnames = true

  # These tags are REQUIRED for EKS and the ALB Ingress Controller to auto-discover subnets later
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }

  tags = {
    Project = var.project_name
  }
}
