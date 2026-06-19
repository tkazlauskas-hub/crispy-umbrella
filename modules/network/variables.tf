variable "name_prefix" {
  type        = string
  description = "Environment prefix for resource names (e.g. \"staging\")."
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for the private subnets (one per AZ)."
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones for the private subnets."
}

variable "aws_region" {
  type        = string
  description = "Region, used to build VPC endpoint service names."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources in this module."
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "Optional CMK ARN to encrypt the VPC flow-log group."
}

variable "flow_log_retention_days" {
  type    = number
  default = 90
}

variable "permissions_boundary_arn" {
  type        = string
  default     = null
  description = "IAM permissions boundary attached to the flow-log role."
}
