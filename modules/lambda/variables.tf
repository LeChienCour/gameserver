variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "lambda_functions" {
  description = "Map of Lambda function names to their deployment package paths"
  type        = map(string)
}

variable "audio_bucket_name" {
  description = "Name of the S3 bucket for audio storage"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
}

variable "event_source" {
  description = "Source for EventBridge events"
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda functions"
  type        = string
}

variable "api_gateway_id" {
  description = "ID of the API Gateway"
  type        = string
}

variable "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

# Lambda Function Configuration
variable "process_audio_timeout" {
  description = "Timeout for the process audio Lambda function in seconds"
  type        = number
  default     = 300
}

variable "process_audio_memory" {
  description = "Memory allocation for the process audio Lambda function in MB"
  type        = number
  default     = 1024
}

variable "validate_audio_timeout" {
  description = "Timeout for the validate audio Lambda function in seconds"
  type        = number
  default     = 30
}

variable "validate_audio_memory" {
  description = "Memory allocation for the validate audio Lambda function in MB"
  type        = number
  default     = 256
}

variable "websocket_timeout" {
  description = "Timeout for WebSocket Lambda functions in seconds"
  type        = number
  default     = 30
}

variable "websocket_memory" {
  description = "Memory allocation for WebSocket Lambda functions in MB"
  type        = number
  default     = 256
}

variable "audio_processing_rule_arn" {
  description = "ARN of the audio processing EventBridge rule"
  type        = string
}

variable "audio_validation_rule_arn" {
  description = "ARN of the audio validation EventBridge rule"
  type        = string
}

variable "stage" {
  description = "Deployment stage (e.g., dev, staging, prod)"
  type        = string
} 