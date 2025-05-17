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