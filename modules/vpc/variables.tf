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

variable "stage" {
  description = "Deployment stage (e.g., dev, staging, prod)"
  type        = string
}