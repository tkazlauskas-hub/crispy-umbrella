# Single table that stores one item per /health request. On-demand billing is a
# good fit for spiky, low-predictability traffic and needs no capacity tuning.

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # Server-side encryption with the customer-managed key (required: SSE).
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  # Continuous backups so the table can be restored to any second in the last
  # 35 days.
  point_in_time_recovery {
    enabled = true
  }

  # Items carry a "ttl" attribute; DynamoDB removes them automatically. This
  # bounds data retention (data minimisation) and storage cost.
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  deletion_protection_enabled = var.deletion_protection_enabled

  tags = merge(var.tags, { Name = var.table_name })
}
