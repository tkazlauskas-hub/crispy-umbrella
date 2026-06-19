output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "invoke_arn" {
  value = aws_lambda_function.this.invoke_arn
}

output "version" {
  value = aws_lambda_function.this.version
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
