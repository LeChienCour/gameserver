variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "lambda_functions" {
  description = "Map of Lambda function zip files"
  type = object({
    process_audio  = string
    validate_audio = string
  })
  default = {
    process_audio  = "lambda/process_audio.zip"
    validate_audio = "lambda/validate_audio.zip"
  }
}

variable "audio_bucket_name" {
  description = "Name of the S3 bucket for audio storage"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
}

variable "event_bus_arn" {
  description = "ARN of the EventBridge event bus"
  type        = string
}

variable "event_source" {
  description = "Source name for EventBridge events"
  type        = string
  default     = "voice-chat"
}

variable "enable_echo_mode" {
  description = "Enable echo mode for testing (audio will be sent back to sender)"
  type        = string
  default     = "false"
}

variable "connections_table" {
  description = "Name of the DynamoDB table for WebSocket connections"
  type        = string
} 