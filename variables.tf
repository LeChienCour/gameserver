# variables.tf

# Common Configuration
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "gameserver"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "gameserver"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# API Gateway Configuration
variable "websocket_prefix" {
  description = "Prefix for WebSocket resources"
  type        = string
  default     = "gameserver"
}

variable "websocket_stage_name" {
  description = "Name of the WebSocket API stage"
  type        = string
  default     = "dev"
}

# Cognito Configuration
variable "admin_role_name" {
  description = "Name of the Cognito Admin Role"
  type        = string
  default     = "gameserver-admin"
}

variable "app_client_name" {
  description = "Name of the Cognito User Pool Client"
  type        = string
  default     = "gameserver-client"
}

variable "user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
  default     = "gameserver-users"
}

# EC2 Instance Configuration
variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = "ami-0c7217cdde317cfec"  # Ubuntu 22.04 LTS
}

variable "instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
  default     = "t3.micro"
}

# EventBridge Configuration
variable "event_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
  default     = "gameserver-events"
}

variable "event_detail_type" {
  description = "Detail type for EventBridge events"
  type        = string
  default     = "AudioProcessing"
}

variable "event_source" {
  description = "Source for EventBridge events"
  type        = string
  default     = "gameserver.audio"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

# Feature Flags
variable "enable_echo_mode" {
  description = "Enable echo mode for audio processing"
  type        = bool
  default     = true
}

# Lambda Configuration
variable "lambda_environment_variables" {
  description = "Additional environment variables for Lambda functions"
  type        = map(string)
  default     = {}
}

variable "lambda_functions" {
  description = "Map of Lambda function names to their deployment package paths"
  type        = map(string)
  default     = {
    connect = "lambda/connect.zip"
    disconnect = "lambda/disconnect.zip"
    message = "lambda/message.zip"
    process_audio = "lambda/process_audio.zip"
    validate_audio = "lambda/validate_audio.zip"
  }
}

# Security Group Configuration
variable "allowed_game_ips" {
  description = "List of IPs allowed to connect to the game server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "game_port" {
  description = "Port for the game server"
  type        = number
  default     = 7777
}

variable "game_protocol" {
  description = "Protocol for the game server"
  type        = string
  default     = "udp"
}

variable "security_group_name" {
  description = "Name of the security group"
  type        = string
  default     = "gameserver-sg"
}

variable "ssh_cidr" {
  description = "CIDR block for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "websocket_port" {
  description = "Port for WebSocket connections"
  type        = number
  default     = 8080
}

# Storage Configuration
variable "audio_bucket_name" {
  description = "Name of the S3 bucket for audio storage"
  type        = string
  default     = "gameserver-audio-storage"
}

variable "connections_table" {
  description = "Name of the DynamoDB table for WebSocket connections"
  type        = string
  default     = "gameserver-connections"
}

# VPC and Network Configuration
variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnets_cidr" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "gameserver-vpc"
}
