output "user_pool_id_parameter_arn" {
  description = "ARN of the Cognito User Pool ID parameter"
  value       = aws_ssm_parameter.user_pool_id.arn
}

output "user_pool_client_id_parameter_arn" {
  description = "ARN of the Cognito User Pool Client ID parameter"
  value       = aws_ssm_parameter.user_pool_client_id.arn
}

output "websocket_api_id_parameter_arn" {
  description = "ARN of the WebSocket API ID parameter"
  value       = aws_ssm_parameter.websocket_api_id.arn
}

output "websocket_stage_url_parameter_arn" {
  description = "ARN of the WebSocket Stage URL parameter"
  value       = aws_ssm_parameter.websocket_stage_url.arn
} 