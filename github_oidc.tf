# ==============================================================================
# GITHUB ACTIONS CI/CD: OIDC FEDERATION
# ==============================================================================
# Lets GitHub Actions assume an AWS role using short-lived federated tokens -
# no AWS access keys stored as GitHub secrets, nothing that can leak and stay
# valid forever.
#
# BOOTSTRAP ORDER (chicken-and-egg, read before touching the workflow file):
#   1. Run `terraform apply` locally (as you already do) with this file in
#      place. This reads the account's existing GitHub OIDC provider (it's
#      account-wide, not per-project - someone on the team already created
#      it) and creates the role below.
#   2. `terraform output -raw github_actions_role_arn` and copy it into the
#      GitHub repo secret AWS_OIDC_ROLE_ARN.
#   3. Only then will .github/workflows/terraform.yml have something valid
#      to assume. See CI_CD_SETUP.md for the full one-time checklist.

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI role, as \"owner/name\". Restricts which repo can federate in - nobody else's Actions workflow can use this role."
  type        = string
  default     = "leederrick36-max/ce12-capstone-iot-project"
}

# Account-wide singleton - IAM OIDC providers are keyed by URL per AWS
# account, not per Terraform state. Someone on the team already created this
# one, so we just read it instead of trying to (re)create it - avoids a
# CreateOpenIDConnectProvider 409 and avoids fighting over ownership of a
# resource other repos/teammates' Terraform may also reference.
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github_actions.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Matches any branch/PR/manual run from this repo only. Tighten to
        # "repo:${var.github_repo}:ref:refs/heads/main" if you want to scope
        # the apply path even further once the workflow is stable.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })
}

# PowerUserAccess covers S3, IoT, SiteWise, Lambda, CloudWatch, EventBridge,
# etc. - everything this repo's .tf files manage - except IAM itself. The
# inline policy below adds just enough IAM permissions for Terraform to also
# create/manage the IAM roles defined elsewhere in this repo (pipeline_role,
# grafana_role, provisioning_role, ...). This is still broad (Resource = "*")
# - fine for a training/capstone sandbox account, but scope the resource ARNs
# down before ever pointing this pattern at a real production account.
resource "aws_iam_role_policy_attachment" "github_actions_power_user" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "github_actions_iam_management" {
  name = "github-actions-iam-management"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
        "iam:UpdateRole", "iam:TagRole", "iam:ListRoles",
        "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
        "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
        "iam:PassRole",
        "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
        "iam:UpdateOpenIDConnectProviderThumbprint", "iam:TagOpenIDConnectProvider"
      ]
      Resource = "*"
    }]
  })
}
