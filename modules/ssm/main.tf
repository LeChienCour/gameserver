# Store User Pool ID
resource "aws_ssm_parameter" "user_pool_id" {
  name        = "/game-server/${var.stage}/cognito/user-pool-id"
  description = "Cognito User Pool ID"
  type        = "String"
  value       = var.user_pool_id
}

# SSM Parameter for Cognito User Pool Client ID
resource "aws_ssm_parameter" "user_pool_client_id" {
  name        = "/game-server/${var.stage}/cognito/user-pool-client-id"
  description = "Cognito User Pool Client ID"
  type        = "String"
  value       = var.user_pool_client_id
}

# SSM Parameter for WebSocket API ID
resource "aws_ssm_parameter" "websocket_api_id" {
  name        = "/game-server/${var.stage}/websocket/api-id"
  description = "WebSocket API ID"
  type        = "String"
  value       = var.websocket_api_id
}

# SSM Parameter for WebSocket Stage URL
resource "aws_ssm_parameter" "websocket_stage_url" {
  name        = "/game-server/${var.stage}/websocket/stage-url"
  description = "WebSocket Stage URL"
  type        = "String"
  value       = var.websocket_stage_url
}

# SSM Parameter for WebSocket API Key
resource "aws_ssm_parameter" "websocket_api_key" {
  name        = "/game-server/${var.stage}/websocket/api-key"
  description = "WebSocket API Key"
  type        = "SecureString"
  value       = var.websocket_api_key
} 