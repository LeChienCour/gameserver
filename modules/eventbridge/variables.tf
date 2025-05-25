variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
}

variable "event_source" {
  description = "Source identifier for events"
  type        = string
}

variable "event_detail_type" {
  description = "Detail type for events"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "process_audio_function_arn" {
  description = "ARN of the process audio Lambda function"
  type        = string
}

variable "validate_audio_function_arn" {
  description = "ARN of the validate audio Lambda function"
  type        = string
} 