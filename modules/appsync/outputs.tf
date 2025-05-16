output "graphql_api_id" {
  description = "The ID of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.voice_chat_api.id
}

output "graphql_api_uri" {
  description = "The URI of the AppSync GraphQL API (HTTPS endpoint)"
  value       = aws_appsync_graphql_api.voice_chat_api.uris["GRAPHQL"]
}

output "api_key_value" {
  description = "The value of the AppSync API Key"
  value       = aws_appsync_api_key.voice_chat_api_default_key.key
  sensitive   = true
}

output "appsync_api_region" {
  description = "The AWS region where the AppSync API is deployed"
  value       = var.region
}