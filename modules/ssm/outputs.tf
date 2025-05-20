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

output "user_pool_id_parameter_name" {
  description = "Name of the Cognito User Pool ID parameter"
  value       = aws_ssm_parameter.user_pool_id.name
}

output "user_pool_client_id_parameter_name" {
  description = "Name of the Cognito User Pool Client ID parameter"
  value       = aws_ssm_parameter.user_pool_client_id.name
}

output "websocket_api_id_parameter_name" {
  description = "Name of the WebSocket API ID parameter"
  value       = aws_ssm_parameter.websocket_api_id.name
}

output "websocket_stage_url_parameter_name" {
  description = "Name of the WebSocket Stage URL parameter"
  value       = aws_ssm_parameter.websocket_stage_url.name
}

output "websocket_api_key_parameter_arn" {
  description = "ARN of the WebSocket API Key parameter"
  value       = aws_ssm_parameter.websocket_api_key.arn
}

output "websocket_api_key_parameter_name" {
  description = "Name of the WebSocket API Key parameter"
  value       = aws_ssm_parameter.websocket_api_key.name
} 