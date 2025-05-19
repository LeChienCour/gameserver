resource "aws_ssm_parameter" "graphql_api_id" {
  name        = "/gameserver/appsync/graphql_api_id"
  description = "The ID of the AppSync GraphQL API"
  type        = "String"
  value       = var.graphql_api_id
  tags = {
    Environment = "production"
    Project     = "GameServer"
  }
}

resource "aws_ssm_parameter" "graphql_api_uri" {
  name        = "/gameserver/appsync/graphql_api_uri"
  description = "The URI of the AppSync GraphQL API (HTTPS endpoint)"
  type        = "String"
  value       = var.graphql_api_uri
  tags = {
    Environment = "production"
    Project     = "GameServer"
  }
}

resource "aws_ssm_parameter" "api_key_value" {
  name        = "/gameserver/appsync/api_key_value"
  description = "The value of the AppSync API Key"
  type        = "SecureString"
  value       = var.api_key_value
  tags = {
    Environment = "production"
    Project     = "GameServer"
  }
}

# SSM Parameter for Cognito User Pool ID
resource "aws_ssm_parameter" "user_pool_id" {
  name        = "/game-server/cognito/user-pool-id"
  description = "Cognito User Pool ID"
  type        = "String"
  value       = var.user_pool_id
}

# SSM Parameter for Cognito User Pool Client ID
resource "aws_ssm_parameter" "user_pool_client_id" {
  name        = "/game-server/cognito/user-pool-client-id"
  description = "Cognito User Pool Client ID"
  type        = "String"
  value       = var.user_pool_client_id
}

# SSM Parameter for WebSocket API ID
resource "aws_ssm_parameter" "websocket_api_id" {
  name        = "/game-server/websocket/api-id"
  description = "WebSocket API ID"
  type        = "String"
  value       = var.websocket_api_id
}

# SSM Parameter for WebSocket Stage URL
resource "aws_ssm_parameter" "websocket_stage_url" {
  name        = "/game-server/websocket/stage-url"
  description = "WebSocket Stage URL"
  type        = "String"
  value       = var.websocket_stage_url
} 