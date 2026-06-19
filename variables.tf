variable "environment" {
  type        = string
  description = "Deployment environment; drives the naming convention."

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be one of: staging, prod."
  }
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs for the private subnets (one per subnet CIDR)."
}

variable "lambda_runtime" {
  type    = string
  default = "python3.13"
}

variable "lambda_memory" {
  type    = number
  default = 128
}

variable "lambda_timeout" {
  type    = number
  default = 10
}

variable "log_level" {
  type    = string
  default = "INFO"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "reserved_concurrency" {
  type        = number
  default     = -1
  description = "Reserved concurrent executions for the Lambda; -1 = unreserved."
}

variable "api_key_required" {
  type    = bool
  default = true
}

variable "throttle_rate" {
  type        = number
  description = "Steady-state requests/second."
}

variable "throttle_burst" {
  type        = number
  description = "Burst capacity."
}

variable "quota_limit" {
  type        = number
  description = "Max requests/day per API key."
}

variable "deletion_protection_enabled" {
  type    = bool
  default = false
}

variable "permissions_boundary_arn" {
  type        = string
  description = "ARN of the IAM permissions boundary applied to all workload roles (from bootstrap output)."
}

variable "data_classification" {
  type        = string
  default     = "internal"
  description = "Data-classification tag applied to all resources (governance)."
}

variable "cost_center" {
  type        = string
  default     = "platform-engineering"
  description = "Cost-center tag applied to all resources (FinOps)."
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}
