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