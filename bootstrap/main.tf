# ---------------------------------------------------------------------------
# Bootstrap: remote state backend + GitHub OIDC + least-privilege deploy role.
# Run once, manually, by an administrator. See bootstrap/README.md.
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # App resources follow the "<env>-resource-name" convention, so we can scope
  # the deploy role to env-prefixed ARNs instead of using wildcards on account.
  env_dynamodb_arns = [for e in var.environments : "arn:aws:dynamodb:${local.region}:${local.account_id}:table/${e}-*"]
  env_lambda_arns   = ["arn:aws:lambda:${local.region}:${local.account_id}:function:*-health-check-*"]
  env_log_arns      = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:*"]
  # Roles created by the stack per environment: <env>-health-check-function-role
  # and <env>-vpc-flow-logs-role. Scoped per env, never account-wide.
  project_role_arns = [for e in var.environments : "arn:aws:iam::${local.account_id}:role/${e}-*"]
}

# ---------------------------------------------------------------------------
# Terraform remote state: encrypted, versioned S3 bucket + DynamoDB lock table.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "state_key" {
  statement {
    sid       = "EnableIamUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "Encrypts Terraform remote state at rest"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.state_key.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}


# Refuse any request to the state bucket that is not over TLS.
data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json
}

resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider: lets the CI pipeline obtain short-lived AWS credentials
# without any long-lived access keys stored in GitHub.
# ---------------------------------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[length(data.tls_certificate.github.certificates) - 1].sha1_fingerprint]
}

# ---------------------------------------------------------------------------
# CI deploy role: assumable only by this repository's main branch and protected
# environments, scoped to the resources this project manages.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    effect  = "Allow"
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

    # Only the main branch and the named GitHub Environments may assume the
    # role. Pull requests and other branches cannot obtain credentials.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      # Built from the environment list, so the template stays correct as
      # environments are added/removed. Allows the main branch plus each
      # protected GitHub Environment to assume the role.
      values = concat(
        ["repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/main"],
        [for e in var.environments : "repo:${var.github_owner}/${var.github_repo}:environment:${e}"],
      )
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.project}-deploy"
  description          = "Assumed by GitHub Actions via OIDC to deploy the health-check stack"
  assume_role_policy   = data.aws_iam_policy_document.deploy_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  # --- Terraform state plumbing -------------------------------------------
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "StateObjectAccess"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "StateLock"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = [aws_dynamodb_table.locks.arn]
  }

  statement {
    sid       = "StateBucketKms"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.state.arn]
  }

  # --- DynamoDB application tables (scoped by env naming convention) -------
  statement {
    sid = "DynamoDbAppTables"
    actions = [
      "dynamodb:CreateTable", "dynamodb:DeleteTable", "dynamodb:DescribeTable",
      "dynamodb:UpdateTable", "dynamodb:DescribeContinuousBackups",
      "dynamodb:UpdateContinuousBackups", "dynamodb:DescribeTimeToLive",
      "dynamodb:UpdateTimeToLive", "dynamodb:TagResource", "dynamodb:UntagResource",
      "dynamodb:ListTagsOfResource",
    ]
    resources = local.env_dynamodb_arns
  }

  # --- Lambda functions (scoped to *-health-check-*) ----------------------
  statement {
    sid = "LambdaManagement"
    actions = [
      "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction",
      "lambda:GetFunctionConfiguration", "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration", "lambda:PublishVersion",
      "lambda:ListVersionsByFunction", "lambda:TagResource", "lambda:UntagResource",
      "lambda:ListTags", "lambda:AddPermission", "lambda:RemovePermission",
      "lambda:GetPolicy", "lambda:PutFunctionConcurrency",
      "lambda:DeleteFunctionConcurrency", "lambda:GetFunctionConcurrency",
    ]
    resources = local.env_lambda_arns
  }

  # --- API Gateway --------------------------------------------------------
  # API Gateway IAM uses control-plane ARNs under /restapis, /apikeys, etc.
  statement {
    sid     = "ApiGatewayManagement"
    actions = ["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:DELETE", "apigateway:PATCH"]
    resources = [
      "arn:aws:apigateway:${local.region}::/restapis",
      "arn:aws:apigateway:${local.region}::/restapis/*",
      "arn:aws:apigateway:${local.region}::/apikeys",
      "arn:aws:apigateway:${local.region}::/apikeys/*",
      "arn:aws:apigateway:${local.region}::/usageplans",
      "arn:aws:apigateway:${local.region}::/usageplans/*",
      "arn:aws:apigateway:${local.region}::/tags/*",
    ]
  }

  # --- IAM for the Lambda execution role (scoped to *-health-check-*) ------
  statement {
    sid       = "CreateProjectRolesWithBoundary"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = local.project_role_arns
    # Anti-privilege-escalation: the pipeline may only create roles that carry
    # the organisation permissions boundary, so a created role can never exceed
    # the boundary's envelope.
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.boundary.arn]
    }
  }

  statement {
    sid = "ManageProjectRoles"
    actions = [
      "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
    ]
    resources = local.project_role_arns
  }

  # PassRole is tightly constrained: the deploy role may only hand the Lambda
  # execution role to the Lambda service, preventing privilege escalation.
  statement {
    sid       = "PassServiceRoles"
    actions   = ["iam:PassRole"]
    resources = local.project_role_arns
    # The deploy role may only hand these roles to the specific AWS services
    # that use them, preventing privilege escalation to arbitrary services.
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }

  # --- KMS application key lifecycle --------------------------------------
  # CreateKey cannot be resource-scoped (the key ARN does not exist yet), so it
  # is bounded by region instead. This is a mandatory wildcard.
  statement {
    sid       = "KmsCreate"
    actions   = ["kms:CreateKey", "kms:CreateAlias", "kms:DeleteAlias", "kms:ListAliases", "kms:TagResource"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # Management of keys already tagged as belonging to this project.
  statement {
    sid = "KmsManageProjectKeys"
    actions = [
      "kms:DescribeKey", "kms:GetKeyPolicy", "kms:PutKeyPolicy",
      "kms:GetKeyRotationStatus", "kms:EnableKeyRotation",
      "kms:ScheduleKeyDeletion", "kms:ListResourceTags", "kms:UntagResource",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = ["homework-health-check"]
    }
  }

  # --- CloudWatch Logs ----------------------------------------------------
  statement {
    sid = "LogsManagement"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
      "logs:TagResource", "logs:UntagResource", "logs:ListTagsForResource",
      "logs:AssociateKmsKey", "logs:DisassociateKmsKey",
    ]
    resources = local.env_log_arns
  }

  # DescribeLogGroups does not support resource-level permissions (mandatory *).
  statement {
    sid       = "LogsDescribe"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # CloudWatch Logs resource policies are account-level (mandatory *), for the WAF log destination.
  statement {
    sid       = "LogsResourcePolicies"
    actions   = ["logs:DescribeResourcePolicies", "logs:PutResourcePolicy", "logs:DeleteResourcePolicy"]
    resources = ["*"]
  }

  # --- VPC / networking ---------------------------------------------------
  # The EC2 networking actions below largely do not support resource-level
  # permissions (this is an AWS API limitation, not a scoping oversight). They
  # are therefore granted on "*" but bounded to the deployment region.
  statement {
    sid = "VpcManagement"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets",
      "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
      "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:ModifySecurityGroupRules",
      "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:DescribeVpcEndpoints",
      "ec2:ModifyVpcEndpoint", "ec2:DescribePrefixLists", "ec2:DescribeNetworkInterfaces",
      "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeAvailabilityZones",
      "ec2:DescribeAccountAttributes",
      "ec2:CreateFlowLogs", "ec2:DeleteFlowLogs", "ec2:DescribeFlowLogs",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # --- WAFv2 (regional web ACL for the API) -------------------------------
  # WAFv2 ARNs embed a generated id, so create/list cannot be pre-scoped; the
  # statement is bounded to the deployment region instead.
  statement {
    sid = "WafV2Management"
    actions = [
      "wafv2:CreateWebACL", "wafv2:DeleteWebACL", "wafv2:UpdateWebACL",
      "wafv2:GetWebACL", "wafv2:ListWebACLs", "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL", "wafv2:GetWebACLForResource",
      "wafv2:ListResourcesForWebACL", "wafv2:TagResource", "wafv2:UntagResource",
      "wafv2:ListTagsForResource",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # Extra read + WAF-logging actions needed for terraform plan refresh and the
  # WAF logging lifecycle. Account/region-level APIs, bounded to the region.
  statement {
    sid       = "ExtraPlanReads"
    actions   = ["ec2:DescribeVpcAttribute", "wafv2:GetLoggingConfiguration", "wafv2:PutLoggingConfiguration", "wafv2:DeleteLoggingConfiguration"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # Read-only identity lookups Terraform performs during plan.
  statement {
    sid       = "ReadOnlyContext"
    actions   = ["sts:GetCallerIdentity", "iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------
# Permissions boundary: the maximum-permissions envelope every workload role
# created by the pipeline must carry. The role's own policy is the actual grant;
# the boundary is a hard ceiling that no inline policy can exceed.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "boundary" {
  statement {
    sid    = "AllowWorkloadServices"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
      "logs:PutRetentionPolicy", "logs:DescribeLogStreams", "logs:DescribeLogGroups",
      "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:DescribeTable",
      "kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey",
      "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
  }

  # Even if an inline policy were misconfigured, a boundaried role can never
  # touch identity, org or key-administration actions.
  statement {
    sid    = "DenyPrivilegeEscalation"
    effect = "Deny"
    actions = [
      "iam:*", "organizations:*", "account:*",
      "kms:PutKeyPolicy", "kms:ScheduleKeyDeletion", "kms:CreateGrant", "kms:RevokeGrant",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${var.project}-permissions-boundary"
  description = "Maximum-permissions envelope for workload roles created by the pipeline"
  policy      = data.aws_iam_policy_document.boundary.json
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.project}-deploy-policy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------------------------------------------------------------------------
# API Gateway account-level CloudWatch Logs role (a per-account/region
# singleton). Created once here so the per-environment stacks can enable access
# and execution logging without fighting over this shared setting.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "apigw_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch" {
  name               = "${var.project}-apigw-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn
}
