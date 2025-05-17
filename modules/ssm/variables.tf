variable "graphql_api_id" {
  description = "The ID of the AppSync GraphQL API"
  type        = string
}

variable "graphql_api_uri" {
  description = "The URI of the AppSync GraphQL API (HTTPS endpoint)"
  type        = string
}

variable "api_key_value" {
  description = "The value of the AppSync API Key"
  type        = string
  sensitive   = true
} 