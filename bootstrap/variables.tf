variable "aws_region" {
  type        = string
  description = "AWS region for the state backend and OIDC/deploy resources."
}

variable "project" {
  type        = string
  default     = "homework-health-check"
  description = "Project tag/name prefix for bootstrap-managed resources."
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name that will hold Terraform state."
}

variable "lock_table_name" {
  type        = string
  default     = "homework-health-check-tf-locks"
  description = "DynamoDB table name used for Terraform state locking."
}

variable "github_owner" {
  type        = string
  description = "GitHub organisation or user that owns the repository."
}

variable "github_repo" {
  type        = string
  description = "Repository name allowed to assume the CI deploy role via OIDC."
}

variable "environments" {
  type        = list(string)
  default     = ["staging", "prod"]
  description = "Environment names; used to scope the deploy role to env-prefixed ARNs."
}
