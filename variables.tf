# variables.tf

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets_cidr" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "game-server-vpc"
}

variable "game_port" {
  description = "Port for game server"
  type        = number
  default     = 25565
}

variable "websocket_port" {
  description = "Port for WebSocket server"
  type        = number
  default     = 8080
}

variable "ssh_cidr" {
  description = "CIDR block for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "game_protocol" {
  description = "Protocol for the game server (tcp or udp)"
  type        = string
  default     = "tcp"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for EC2"
  type        = string
  default     = "t3.medium"
}

variable "security_group_name" {
  description = "Name of the security group"
  type        = string
  default     = "game-server-sg"
}

variable "user_pool_name" {
  description = "Name of the Cognito user pool"
  type        = string
  default     = "game-server-users"
}

variable "app_client_name" {
  description = "Name of the Cognito app client"
  type        = string
  default     = "game-server-client"
}

variable "admin_role_name" {
  description = "Name of the admin role"
  type        = string
  default     = "game-server-admin"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "game-server"
}

variable "websocket_prefix" {
  description = "Prefix for WebSocket resources"
  type        = string
  default     = "game-server-ws"
}

variable "websocket_stage_name" {
  description = "Name of the WebSocket API stage"
  type        = string
  default     = "test"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "lambda_functions" {
  description = "Map of Lambda function zip files"
  type = object({
    connect    = string
    disconnect = string
    message    = string
  })
  default = {
    connect    = "lambda/connect.zip"
    disconnect = "lambda/disconnect.zip"
    message    = "lambda/message.zip"
  }
}

# EventBridge variables
variable "eventbridge_prefix" {
  description = "Prefix for EventBridge resources"
  type        = string
  default     = "game-server"
}

variable "eventbridge_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
  default     = "game-server-events"
}

variable "eventbridge_event_source" {
  description = "Source name for EventBridge events"
  type        = string
  default     = "game-server.audio"
}

variable "eventbridge_event_detail_type" {
  description = "Detail type for EventBridge events"
  type        = string
  default     = "SendAudioEvent"
}

variable "eventbridge_log_retention_days" {
  description = "Number of days to retain EventBridge logs"
  type        = number
  default     = 30
}

variable "enable_echo_mode" {
  description = "Enable echo mode for testing (audio will be sent back to sender)"
  type        = string
  default     = "false"
}
