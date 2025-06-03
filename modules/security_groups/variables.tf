variable "vpc_id" {
  description = "ID of the VPC"
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

variable "security_group_name" {
  description = "Name of the security group"
  type        = string
  default     = "game-server-sg"
}

variable "allowed_game_ips" {
  description = "List of allowed IPs for game server access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "stage" {
  description = "Deployment stage (e.g., dev, staging, prod)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}
