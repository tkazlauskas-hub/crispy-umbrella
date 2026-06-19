environment          = "prod"
aws_region           = "eu-central-1"
availability_zones   = ["eu-central-1a", "eu-central-1b"]
vpc_cidr             = "10.20.0.0/16"
private_subnet_cidrs = ["10.20.1.0/24", "10.20.2.0/24"]

# Production: higher limits, deletion protection on.
throttle_rate        = 100
throttle_burst       = 200
quota_limit          = 1000000
reserved_concurrency = 50
log_retention_days   = 90

deletion_protection_enabled = true
