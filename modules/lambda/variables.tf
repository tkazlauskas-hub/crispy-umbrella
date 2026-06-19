variable "function_name" {
  type        = string
  description = "Full function name following the env-resource-name convention."
}

variable "source_dir" {
  type        = string
  description = "Path to the Lambda source directory to package."
}

variable "runtime" {
  type        = string
  default     = "python3.13"
  description = "Lambda managed runtime."
}

variable "handler" {
  type        = string
  default     = "handler.handler"
  description = "Module.function entrypoint."
}

variable "table_name" {
  type        = string
  description = "DynamoDB table name passed to the function as TABLE_NAME."
}

variable "table_arn" {
  type        = string
  description = "DynamoDB table ARN, used to scope the execution policy."
}

variable "kms_key_arn" {
  type        = string
  description = "CMK ARN; granted to the role only via DynamoDB."
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "Optional CMK ARN to encrypt the function log group. Null = default encryption."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet ids for the function's ENIs."
}

variable "security_group_id" {
  type        = string
  description = "Security group id for the function's ENIs."
}

variable "aws_region" {
  type        = string
  description = "Region, used in the kms:ViaService condition."
}

variable "log_retention_days" {
  type        = number
  default     = 30
}

variable "reserved_concurrency" {
  type        = number
  default     = -1
  description = "Reserved concurrent executions; -1 means unreserved."
}

variable "memory_size" {
  type    = number
  default = 128
}

variable "timeout" {
  type    = number
  default = 10
}

variable "log_level" {
  type    = string
  default = "INFO"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "permissions_boundary_arn" {
  type        = string
  default     = null
  description = "IAM permissions boundary attached to the execution role."
}
