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