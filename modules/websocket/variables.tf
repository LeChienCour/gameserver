variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  default     = "game-server"
}

variable "stage_name" {
  description = "Name of the WebSocket API stage"
  type        = string
  default     = "test"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "test"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "game-server"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "event_bus_arn" {
  description = "ARN of the EventBridge event bus"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
}

variable "event_source" {
  description = "Source name for EventBridge events"
  type        = string
}

variable "connections_table" {
  description = "Name of the DynamoDB table for WebSocket connections"
  type        = string
}

variable "lambda_functions" {
  description = "Map of Lambda function file paths"
  type = object({
    connect    = string
    disconnect = string
    message    = string
    audio      = string
  })
  default = {
    connect    = "lambda/connect.zip"
    disconnect = "lambda/disconnect.zip"
    message    = "lambda/message.zip"
    audio      = "lambda/audio.zip"
  }
}

variable "lambda_environment_variables" {
  description = "Environment variables for Lambda functions"
  type        = map(string)
  default     = {}
}

variable "audio_bucket_arn" {
  description = "ARN of the S3 bucket for audio storage"
  type        = string
} 