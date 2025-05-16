output "appsync_graphql_api_id" {
  description = "The ID of the AppSync GraphQL API"
  value       = module.appsync.graphql_api_id
}

output "appsync_graphql_api_uri" {
  description = "The URI of the AppSync GraphQL API (HTTPS endpoint)"
  value       = module.appsync.graphql_api_uri
}

output "appsync_api_key_value" {
  description = "The value of the AppSync API Key for initial testing"
  value       = module.appsync.api_key_value
  sensitive   = true
}

output "appsync_api_region" {
  description = "The AWS region where the AppSync API is deployed"
  value       = var.region
}

output "aws_account_id" {
  description = "The AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}