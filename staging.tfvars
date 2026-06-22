environment          = "staging"
aws_region           = "eu-central-1"
availability_zones   = ["eu-central-1a", "eu-central-1b"]
vpc_cidr             = "10.10.0.0/16"
private_subnet_cidrs = ["10.10.1.0/24", "10.10.2.0/24"]

# Staging: modest limits, no deletion protection.
throttle_rate        = 20
throttle_burst       = 40
quota_limit          = 50000
reserved_concurrency = -1
log_retention_days   = 14

deletion_protection_enabled = false
