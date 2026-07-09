# Registers GitHub's OIDC issuer as a trusted identity provider in this AWS account.
# This is what lets GitHub Actions request short-lived AWS credentials directly,
# instead of storing a long-lived Access Key/Secret as a GitHub secret.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # AWS-published thumbprints for GitHub's OIDC certificate chain
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# The IAM role that GitHub Actions workflows will assume.
# The trust policy below is scoped so ONLY workflows running from
# Gadede/eks-learning-infra can assume this role - not any GitHub repo.
resource "aws_iam_role" "github_actions" {
  name = "github-actions-eks-learning"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Gadede/EKS-Infra:*"
          }
        }
      }
    ]
  })

  tags = {
    Project = var.project_name
  }
}

# Scoped least-privilege policy instead of AdministratorAccess.
# Covers exactly what Phases 2-7 need: VPC/EC2 networking, EKS cluster
# management, and IAM role management restricted to this project's
# naming prefix, plus access to the specific S3 state bucket.
#
# NOTE ON LIMITS: EC2 and EKS cluster-creation actions (e.g. ec2:CreateVpc,
# eks:CreateCluster) do not support resource-level ARN restrictions in AWS -
# this is an AWS service limitation, not a choice we're making. Where AWS
# does support scoping (IAM roles, the S3 bucket, EKS resource actions on
# an existing cluster), it's applied below.
data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "github_actions_scoped" {
  name        = "github-actions-eks-learning-policy"
  description = "Least-privilege policy for GitHub Actions to manage the eks-learning project"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2NetworkingNoResourceLevelSupport"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
          "ec2:AllocateAddress", "ec2:ReleaseAddress",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags", "ec2:DeleteTags",
          "ec2:RunInstances", "ec2:TerminateInstances"
        ]
        # No Resource-level restriction possible for these actions in AWS -
        # restricted instead by requiring the us-east-2 region.
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "us-east-2"
          }
        }
      },
      {
        Sid    = "EKSClusterManagement"
        Effect = "Allow"
        Action = [
          "eks:*"
        ]
        Resource = [
          "arn:aws:eks:us-east-2:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}*",
          "arn:aws:eks:us-east-2:${data.aws_caller_identity.current.account_id}:nodegroup/${var.cluster_name}*/*/*",
          "arn:aws:eks:us-east-2:${data.aws_caller_identity.current.account_id}:addon/${var.cluster_name}*/*/*",
          "arn:aws:eks:us-east-2:${data.aws_caller_identity.current.account_id}:access-entry/${var.cluster_name}*/*"
        ]
      },
      {
        Sid    = "EKSAutoScalingAndLaunchTemplates"
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup", "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup", "autoscaling:Describe*",
          "autoscaling:CreateOrUpdateTags", "autoscaling:DeleteTags",
          "ec2:CreateLaunchTemplate", "ec2:DeleteLaunchTemplate", "ec2:ModifyLaunchTemplate",
          "ec2:CreateLaunchTemplateVersion"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "us-east-2"
          }
        }
      },
      {
        Sid    = "KMSForEKSSecretsEncryption"
        Effect = "Allow"
        Action = [
          # Write actions
          "kms:CreateKey", "kms:ScheduleKeyDeletion",
          "kms:TagResource", "kms:UntagResource",
          "kms:EnableKeyRotation", "kms:PutKeyPolicy",
          "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias",
          "kms:CreateGrant", "kms:RevokeGrant",
          # Read-only actions - broadened for the same reason as IAM: Terraform's
          # refresh step calls many individual Get/Describe/List KMS actions
          # (key rotation status, key policy, resource tags, grants) that aren't
          # worth enumerating one at a time.
          "kms:Describe*",
          "kms:Get*",
          "kms:List*"
        ]
        # kms:CreateKey has no ARN to scope to before the key exists - same
        # AWS limitation as EC2 create actions. Restricted by region instead.
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "us-east-2"
          }
        }
      },
      {
        Sid    = "CloudWatchLogsForEKSControlPlane"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
          "logs:DescribeLogGroups", "logs:TagResource", "logs:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:logs:us-east-2:${data.aws_caller_identity.current.account_id}:log-group:*"
        ]
      },
      {
        Sid    = "IAMScopedToProjectPrefix"
        Effect = "Allow"
        Action = [
          # Write actions - tightly scoped, these can create/modify/delete
          "iam:CreateRole", "iam:DeleteRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:TagRole", "iam:TagPolicy", "iam:TagOpenIDConnectProvider", "iam:TagInstanceProfile",
          "iam:CreateServiceLinkedRole",
          "iam:PassRole",
          # Read-only actions - safe to broaden since they can't change anything.
          "iam:Get*",
          "iam:List*"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eksctl-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-eks-learning",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/${var.cluster_name}*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.project_name}-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/github-actions-eks-learning-policy",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AWSLoadBalancerControllerIAMPolicy-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/*"
        ]
      },
      {
        Sid    = "S3StateBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::richeks-tfstate-bucket",
          "arn:aws:s3:::richeks-tfstate-bucket/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_scoped" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_scoped.arn
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role GitHub Actions will assume"
  value       = aws_iam_role.github_actions.arn
}
