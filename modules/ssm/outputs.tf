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