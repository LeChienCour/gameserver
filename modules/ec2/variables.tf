variable "ami_id" {
  description = "AMI ID for the game server"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet for the instance"
  type        = string
}

variable "security_group_id" {
  description = "ID of the security group for the instance"
  type        = string
}
variable "game_port" {
  description = "Port for the game server"
  type = number
}