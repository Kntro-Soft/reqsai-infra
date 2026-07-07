# Fetched live instead of hardcoded — GitHub has rotated this before, and a
# stale value silently breaks every workflow using the provider.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Lets GitHub Actions assume AWS roles via short-lived OIDC tokens instead
# of long-lived access keys stored as repo secrets. One provider per AWS
# account, shared by every repo's deploy workflow.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[length(data.tls_certificate.github.certificates) - 1].sha1_fingerprint]
}

# --- reqsai-api: build/push to ECR, deploy to ECS ---

data "aws_iam_policy_document" "github_actions_api_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Kntro-Soft/reqsai-api:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_api" {
  name               = "reqsai-${var.environment}-github-actions-api"
  assume_role_policy = data.aws_iam_policy_document.github_actions_api_assume_role.json
}

data "aws_iam_policy_document" "github_actions_api_permissions" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [aws_ecr_repository.reqsai_api.arn]
  }

  statement {
    sid       = "RegisterTaskDefinition"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
    resources = ["*"] # ECS does not support resource-level scoping for these actions
  }

  statement {
    sid       = "DeployService"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = [aws_ecs_service.reqsai_api.id]
  }

  # ECS needs to assume these roles on the CI's behalf when it registers a
  # task definition that references them.
  statement {
    sid       = "PassEcsRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_task_execution.arn, aws_iam_role.ecs_task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github_actions_api_permissions" {
  name   = "deploy-reqsai-api"
  role   = aws_iam_role.github_actions_api.id
  policy = data.aws_iam_policy_document.github_actions_api_permissions.json
}

# --- reqsai-web: sync build output to S3, invalidate CloudFront ---

data "aws_iam_policy_document" "github_actions_web_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:Kntro-Soft/reqsai-web:*"]
    }
  }
}

resource "aws_iam_role" "github_actions_web" {
  name               = "reqsai-${var.environment}-github-actions-web"
  assume_role_policy = data.aws_iam_policy_document.github_actions_web_assume_role.json
}

data "aws_iam_policy_document" "github_actions_web_permissions" {
  statement {
    sid       = "SyncBucket"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.web.arn, "${aws_s3_bucket.web.arn}/*"]
  }

  statement {
    sid       = "InvalidateCache"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.web.arn]
  }
}

resource "aws_iam_role_policy" "github_actions_web_permissions" {
  name   = "deploy-reqsai-web"
  role   = aws_iam_role.github_actions_web.id
  policy = data.aws_iam_policy_document.github_actions_web_permissions.json
}
