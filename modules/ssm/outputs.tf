output "graphql_api_id_parameter_name" {
  description = "The name of the SSM parameter storing the GraphQL API ID"
  value       = aws_ssm_parameter.graphql_api_id.name
}

output "graphql_api_uri_parameter_name" {
  description = "The name of the SSM parameter storing the GraphQL API URI"
  value       = aws_ssm_parameter.graphql_api_uri.name
}

output "api_key_value_parameter_name" {
  description = "The name of the SSM parameter storing the API Key value"
  value       = aws_ssm_parameter.api_key_value.name
}

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