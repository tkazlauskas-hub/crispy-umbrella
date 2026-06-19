variable "name_prefix" {
  type        = string
  description = "Environment prefix used for the alias and log-group key policy."
}

variable "aws_region" {
  type        = string
  description = "Region, used to scope the CloudWatch Logs key-policy condition."
}

variable "account_id" {
  type        = string
  description = "AWS account id, used in the key policy ARNs."
}

variable "deletion_window_in_days" {
  type        = number
  default     = 7
  description = "Waiting period before the key is deleted."
}

variable "tags" {
  type    = map(string)
  default = {}
}
