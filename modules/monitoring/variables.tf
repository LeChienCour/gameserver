variable "prefix" {
  description = "Prefix for monitoring resource names"
  type        = string
}

variable "stage" {
  description = "Deployment stage (e.g., dev, staging, prod)"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region for dashboard widgets"
  type        = string
  default     = "us-east-1"
}

variable "instance_id" {
  description = "EC2 instance ID of the Minecraft server (null when enable_ec2_server is false)"
  type        = string
  default     = null
}

variable "websocket_api_id" {
  description = "WebSocket API Gateway ID"
  type        = string
}

variable "event_dlq_name" {
  description = "Name of the EventBridge SQS Dead Letter Queue"
  type        = string
}

variable "lambda_function_names" {
  description = "Map of Lambda function names to monitor"
  type        = map(string)
}
