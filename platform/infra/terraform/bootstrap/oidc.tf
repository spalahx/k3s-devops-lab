# GitHub Actions authenticates to AWS with short-lived OIDC tokens; no access keys are stored in GitHub.
#   plan role  - read-only, for pull requests of this repository
#   apply role - for jobs that run in the GitHub Environment named by var.apply_environment
#                (configure required reviewers on that Environment)

locals {
  oidc_host = "token.actions.githubusercontent.com"

  subjects = {
    plan  = "repo:${var.github_repository}:pull_request"
    apply = "repo:${var.github_repository}:environment:${var.apply_environment}"
  }

  trust_policies = {
    for role, subject in local.subjects : role => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_host}:aud" = "sts.amazonaws.com"
            "${local.oidc_host}:sub" = subject
          }
        }
      }]
    })
  }

  state_bucket_arn = module.state_bucket.arn
  read_only_arn    = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
  lab_prefix       = "${var.project}-lab"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

# ---- plan role -------------------------------------------------------------

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-gha-plan"
  assume_role_policy   = local.trust_policies["plan"]
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = local.read_only_arn
}

resource "aws_iam_role_policy" "plan_state" {
  name = "state-read-and-lock"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListState"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${local.state_bucket_arn}/*"]
      },
      {
        Sid      = "LockState"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_bucket_arn}/*.tflock"]
      },
    ]
  })
}

# ---- apply role ------------------------------------------------------------

resource "aws_iam_role" "apply" {
  name                 = "${var.project}-gha-apply"
  assume_role_policy   = local.trust_policies["apply"]
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "apply_read_only" {
  role       = aws_iam_role.apply.name
  policy_arn = local.read_only_arn
}

# Scoped to what the lab environment needs. Names created by the lab start with "<project>-lab".
# To be tightened later with IAM Access Analyzer policy generation (lab L15).
resource "aws_iam_policy" "apply_lab" {
  name = "${var.project}-gha-apply-lab"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Ec2InRegion"
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.region }
        }
      },
      {
        Sid    = "SessionManager"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:DescribeInstanceInformation",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:AddTagsToResource",
          "ssm:ListTagsForResource",
          "ssm:DescribeParameters",
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = var.region }
        }
      },
      {
        Sid    = "LabIdentities"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole",
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",
        ]
        Resource = [
          "arn:${local.partition}:iam::${local.account_id}:role/${local.lab_prefix}-*",
          "arn:${local.partition}:iam::${local.account_id}:instance-profile/${local.lab_prefix}-*",
          "arn:${local.partition}:iam::${local.account_id}:policy/${local.lab_prefix}-*",
        ]
      },
      {
        Sid      = "PassLabRolesToEc2"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = ["arn:${local.partition}:iam::${local.account_id}:role/${local.lab_prefix}-*"]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" }
        }
      },
      {
        Sid    = "LabBuckets"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:ListBucket",
          "s3:GetBucket*",
          "s3:PutBucket*",
          "s3:DeleteBucketPolicy",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
        ]
        Resource = [
          "arn:${local.partition}:s3:::${local.lab_prefix}-*",
          "arn:${local.partition}:s3:::${local.lab_prefix}-*/*",
        ]
      },
      {
        Sid      = "ListState"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [local.state_bucket_arn]
      },
      {
        Sid      = "ReadWriteState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${local.state_bucket_arn}/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "apply_lab" {
  role       = aws_iam_role.apply.name
  policy_arn = aws_iam_policy.apply_lab.arn
}
