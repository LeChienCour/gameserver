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

variable "user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  type        = string
}

variable "websocket_api_id" {
  description = "WebSocket API ID"
  type        = string
}

variable "websocket_stage_url" {
  description = "WebSocket Stage URL"
  type        = string
} 