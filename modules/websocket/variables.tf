variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  default     = "voice-chat"
}

variable "stage_name" {
  description = "Name of the WebSocket API stage"
  type        = string
  default     = "prod"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "voice-chat"
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

variable "lambda_functions" {
  description = "Map of Lambda function file paths"
  type = object({
    connect    = string
    disconnect = string
    message    = string
  })
} 