variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for EC2"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "Subnet ID for EC2 instance"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for EC2 instance"
  type        = string
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

variable "user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
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

variable "key_name" {
  description = "Name of the AWS key pair to use for SSH access"
  type        = string
}

variable "minecraft_version" {
  description = "Version of Minecraft to install"
  type        = string
  default     = "1.21.1"
}

variable "neoforge_version" {
  description = "Version of NeoForge to install"
  type        = string
  default     = "1.21.1"
}

variable "server_memory" {
  description = "Amount of memory to allocate to the Minecraft server (in GB)"
  type        = number
  default     = 4
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "java_parameters" {
  description = "Additional Java parameters for the Minecraft server"
  type        = string
  default     = ""
}