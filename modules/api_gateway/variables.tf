variable "prefix" {
  description = "Prefix to be used in resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "stage_name" {
  description = "Name of the API Gateway stage"
  type        = string
}

variable "cloudwatch_role_arn" {
  description = "ARN of the CloudWatch role for API Gateway"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
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

# Lambda ARNs for WebSocket integrations
variable "lambda_connect_arn" {
  description = "ARN of the WebSocket $connect Lambda function"
  type        = string
}

variable "lambda_disconnect_arn" {
  description = "ARN of the WebSocket $disconnect Lambda function"
  type        = string
}

variable "lambda_message_arn" {
  description = "ARN of the WebSocket $default and message Lambda function"
  type        = string
}

# Optional VPC Configuration
variable "vpc_id" {
  description = "ID of the VPC (optional)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for VPC endpoint (optional)"
  type        = list(string)
  default     = []
}

variable "vpc_endpoint_id" {
  description = "ID of the VPC endpoint (optional)"
  type        = string
  default     = null
}

variable "security_groups" {
  description = "List of security group IDs for VPC endpoint (optional)"
  type        = list(string)
  default     = []
} 