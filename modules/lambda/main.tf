# Packages and deploys the health-check function into private subnets with a
# tightly scoped execution role. Packaging happens here (archive_file), so the
# pipeline produces the deployment artifact deterministically and publishes an
# immutable version on every change.

data "archive_file" "package" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/build/${var.function_name}.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn

  tags = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.function_name}-role"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

# Least-privilege execution policy. Every statement is scoped to a specific
# resource ARN, except the EC2 ENI actions, which the EC2 API does not support
# resource-level permissions for (a mandatory wildcard, called out below).
data "aws_iam_policy_document" "exec" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid       = "WriteToRequestsTable"
    actions   = ["dynamodb:PutItem"]
    resources = [var.table_arn]
  }

  # The function never calls KMS directly; DynamoDB uses the key on its behalf.
  # The ViaService condition guarantees the role can only exercise the key
  # through DynamoDB.
  statement {
    sid       = "UseKeyViaDynamoDB"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["dynamodb.${var.aws_region}.amazonaws.com"]
    }
  }

  # Required for a VPC-attached Lambda to manage its elastic network interfaces.
  # These EC2 actions do not support resource-level permissions, so "*" here is
  # mandated by the AWS API rather than a least-privilege shortcut.
  statement {
    sid = "ManageVpcEni"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "exec" {
  name   = "${var.function_name}-policy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.exec.json
}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = aws_iam_role.this.arn
  runtime       = var.runtime
  handler       = var.handler
  timeout       = var.timeout
  memory_size   = var.memory_size

  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256

  # Publish an immutable version on each code change (automated versioning).
  publish = true

  reserved_concurrent_executions = var.reserved_concurrency

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      TABLE_NAME = var.table_name
      LOG_LEVEL  = var.log_level
    }
  }

  depends_on = [
    aws_iam_role_policy.exec,
    aws_cloudwatch_log_group.this,
  ]

  tags = var.tags
}
