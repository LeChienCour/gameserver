variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "stage_name" {
  description = "Name of the WebSocket stage"
  type        = string
  default     = "prod"
}

variable "cloudwatch_role_arn" {
  description = "ARN of the IAM role for CloudWatch logging"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "throttle_burst_limit" {
  description = "Maximum number of requests that can be made in a burst"
  type        = number
  default     = 100
}

variable "throttle_rate_limit" {
  description = "Maximum number of requests per second"
  type        = number
  default     = 50
}

variable "quota_limit" {
  description = "Maximum number of requests per month"
  type        = number
  default     = 1000000
} 