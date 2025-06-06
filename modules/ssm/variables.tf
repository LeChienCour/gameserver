variable "stage" {
  description = "Deployment stage name (e.g., dev, staging, prod)"
  type        = string
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

variable "websocket_api_key" {
  description = "API key for WebSocket API authentication"
  type        = string
  sensitive   = true
} 