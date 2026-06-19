output "deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN GitHub Actions variable."
  value       = aws_iam_role.deploy.arn
}

output "state_bucket" {
  description = "Set this as the TF_STATE_BUCKET GitHub Actions variable."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "Set this as the TF_LOCK_TABLE GitHub Actions variable."
  value       = aws_dynamodb_table.locks.name
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "region" {
  value = var.aws_region
}

output "permissions_boundary_arn" {
  description = "Set this as the TF_VAR_permissions_boundary_arn GitHub Actions variable."
  value       = aws_iam_policy.boundary.arn
}
