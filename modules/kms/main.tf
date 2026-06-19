# Customer-managed KMS key used to encrypt the DynamoDB table and the project's
# CloudWatch log groups. Key rotation is enabled. The key policy grants the
# account root the ability to delegate access via IAM (the AWS-recommended
# baseline that prevents lock-out) and explicitly lets CloudWatch Logs use the
# key for this environment's log groups only.

data "aws_iam_policy_document" "key" {
  statement {
    sid       = "EnableIamUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    # Restrict to log groups that belong to this environment, so the key cannot
    # be used to encrypt arbitrary log groups in the account.
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/${var.name_prefix}-*",
        "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/${var.name_prefix}-*",
        "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:aws-waf-logs-${var.name_prefix}-*",
      ]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "${var.name_prefix} health-check encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.key.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-health-check-key" })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name_prefix}-health-check"
  target_key_id = aws_kms_key.this.key_id
}
