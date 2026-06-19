output "health_endpoint" {
  description = "Full URL of the /health endpoint."
  value       = module.api.invoke_url
}

output "api_key_id" {
  description = "API key id. Retrieve the value with: aws apigateway get-api-key --api-key <id> --include-value"
  value       = module.api.api_key_id
}

output "table_name" {
  value = module.dynamodb.table_name
}

output "function_name" {
  value = module.lambda.function_name
}

output "lambda_version" {
  value = module.lambda.version
}

output "vpc_id" {
  value = module.network.vpc_id
}
