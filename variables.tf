# variables.tf

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnets_cidr" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of Availability Zones for the VPC"
  type        = list(string)
}

variable "vpc_name" {
  description = "Name for the VPC"
  type        = string
}

variable "game_port" {
  description = "Port for the game server"
  type        = number
}

variable "ssh_cidr" {
  description = "CIDR block for SSH access"
  type        = string
}

variable "audio_port" {
  description = "Port for audio chat"
  type        = number
}

variable "game_protocol" {
  description = "Protocol for the game server (tcp or udp)"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the game server"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "security_group_name" {
  description = "Name of the security group for the instance"
  type        = string
}

variable "user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
}

variable "app_client_name" {
  description = "Name of the Cognito App Client"
  type        = string
}

variable "admin_role_name" {
  description = "Name of the admin role"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

# EventBridge variables
variable "eventbridge_prefix" {
  description = "Prefix to be used for EventBridge resource names"
  type        = string
  default     = "voice-chat"
}

variable "eventbridge_bus_name" {
  description = "Name of the custom EventBridge event bus"
  type        = string
  default     = "voice-chat-event-bus"
}

variable "eventbridge_event_source" {
  description = "Source identifier for EventBridge events"
  type        = string
  default     = "appsync.voicechat"
}

variable "eventbridge_event_detail_type" {
  description = "Detail type for EventBridge events"
  type        = string
  default     = "SendAudioEvent"
}

variable "eventbridge_log_retention_days" {
  description = "Number of days to retain CloudWatch logs for EventBridge events"
  type        = number
  default     = 30
}
