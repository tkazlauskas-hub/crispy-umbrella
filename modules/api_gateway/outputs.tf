output "invoke_url" {
  description = "Base URL of the /health endpoint."
  value       = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.this.stage_name}/health"
}

output "rest_api_id" {
  value = aws_api_gateway_rest_api.this.id
}

# The API key id (not its secret value). Retrieve the value with:
#   aws apigateway get-api-key --api-key <id> --include-value
output "api_key_id" {
  value = var.api_key_required ? aws_api_gateway_api_key.this[0].id : null
}
