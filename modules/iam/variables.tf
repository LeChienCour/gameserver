variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "audio_bucket_name" {
  description = "Name of the S3 bucket for audio storage"
  type        = string
}

variable "event_bus_arn" {
  description = "ARN of the EventBridge event bus"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "stage" {
  description = "Deployment stage (e.g., dev, staging, prod)"
  type        = string
} 