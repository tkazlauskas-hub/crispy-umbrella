variable "table_name" {
  type        = string
  description = "Full table name, already following the env-resource-name convention."
}

variable "kms_key_arn" {
  type        = string
  description = "Customer-managed KMS key ARN used for server-side encryption."
}

variable "deletion_protection_enabled" {
  type        = bool
  default     = false
  description = "Block accidental table deletion (enabled in prod)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
