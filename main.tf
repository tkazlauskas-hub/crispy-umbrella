data "aws_caller_identity" "current" {}

module "network" {
  source               = "./modules/network"
  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones        = var.availability_zones
  aws_region                = var.aws_region
  log_kms_key_arn           = module.kms.key_arn
  permissions_boundary_arn  = var.permissions_boundary_arn
  tags                      = local.common_tags
}

module "kms" {
  source      = "./modules/kms"
  name_prefix = local.name_prefix
  aws_region  = var.aws_region
  account_id  = data.aws_caller_identity.current.account_id
  tags        = local.common_tags
}

module "dynamodb" {
  source                      = "./modules/dynamodb"
  table_name                  = local.table_name
  kms_key_arn                 = module.kms.key_arn
  deletion_protection_enabled = var.deletion_protection_enabled
  tags                        = local.common_tags
}

module "lambda" {
  source               = "./modules/lambda"
  function_name        = local.function_name
  source_dir           = "${path.module}/lambda"
  runtime              = var.lambda_runtime
  handler              = "app.handler"
  table_name           = module.dynamodb.table_name
  table_arn            = module.dynamodb.table_arn
  kms_key_arn          = module.kms.key_arn
  log_kms_key_arn      = module.kms.key_arn
  subnet_ids           = module.network.private_subnet_ids
  security_group_id    = module.network.lambda_security_group_id
  aws_region           = var.aws_region
  log_retention_days   = var.log_retention_days
  reserved_concurrency = var.reserved_concurrency
  memory_size          = var.lambda_memory
  timeout              = var.lambda_timeout
  log_level                = var.log_level
  permissions_boundary_arn = var.permissions_boundary_arn
  tags                     = local.common_tags
}

module "api" {
  source               = "./modules/api_gateway"
  api_name             = local.api_name
  stage_name           = var.environment
  lambda_function_name = module.lambda.function_name
  lambda_invoke_arn    = module.lambda.invoke_arn
  aws_region           = var.aws_region
  api_key_required     = var.api_key_required
  throttle_rate        = var.throttle_rate
  throttle_burst       = var.throttle_burst
  quota_limit          = var.quota_limit
  log_kms_key_arn      = module.kms.key_arn
  log_retention_days   = var.log_retention_days
  tags                 = local.common_tags
}
