variable "api_name" {
  type        = string
  description = "Full API name following the env-resource-name convention."
}

variable "stage_name" {
  type        = string
  description = "Stage name (the environment)."
}

variable "lambda_function_name" {
  type        = string
  description = "Name of the Lambda to grant invoke permission to."
}

variable "lambda_invoke_arn" {
  type        = string
  description = "invoke_arn of the Lambda for the proxy integration."
}

variable "aws_region" {
  type = string
}

variable "api_key_required" {
  type        = bool
  default     = true
  description = "Require an API key on the methods and create a usage plan key."
}

variable "throttle_rate" {
  type        = number
  description = "Steady-state requests per second (usage plan + method settings)."
}

variable "throttle_burst" {
  type        = number
  description = "Burst capacity (usage plan + method settings)."
}

variable "quota_limit" {
  type        = number
  description = "Maximum requests per day per API key."
}

variable "log_kms_key_arn" {
  type        = string
  default     = null
  description = "Optional CMK ARN to encrypt the access log group."
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "enable_waf" {
  type        = bool
  default     = true
  description = "Attach a WAFv2 web ACL (rate limiting + AWS managed rules) to the stage."
}

variable "waf_rate_limit" {
  type        = number
  default     = 2000
  description = "Max requests per 5-minute window per source IP before WAF blocks."
}

variable "enable_waf_logging" {
  type        = bool
  default     = true
  description = "Ship WAF events to a dedicated CloudWatch log group."
}
