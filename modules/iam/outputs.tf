output "lambda_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda IAM role"
  value       = aws_iam_role.lambda_role.name
}

output "cloudwatch_role_arn" {
  description = "ARN of the API Gateway CloudWatch IAM role"
  value       = aws_iam_role.api_gateway_cloudwatch.arn
} 