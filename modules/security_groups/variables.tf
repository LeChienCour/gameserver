variable "vpc_id" {
  description = "ID of the VPC"
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

variable "security_group_name" {
  description = "Name of the security group for the instance"
  type        = string
}

variable "allowed_game_ips" {
  description = "List of IPs allowed for game"
  type        = list(string)
}

variable "allowed_audio_ips" {
  description = "List of IPs allowed for audio"
  type        = list(string)
}
