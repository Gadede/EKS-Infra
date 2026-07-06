# The IAM role that can CREATE the EKS cluster is not automatically allowed
# to run kubectl commands INSIDE it - those are two separate permission
# systems (AWS IAM vs Kubernetes RBAC). This access entry bridges them,
# granting the GitHub Actions role cluster-admin rights over the Kubernetes API.
# Static access entry for the human operator (Richy) - explicit and fixed,
# unlike the dynamic "cluster creator" flag which shifted to whichever
# identity ran the most recent apply.

resource "aws_eks_access_entry" "human_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::358604342827:user/Richy"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "human_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::358604342827:user/Richy"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
