variable "api_name" {
  description = "The name of the AppSync API"
  type        = string
  default     = "voice-chat-api"
}

variable "region" {
  description = "The AWS region"
  type        = string
  default     = "us-east-1"
}

variable "user_pool_id" {
  description = "The ID of the Cognito user pool"
  type        = string
}
