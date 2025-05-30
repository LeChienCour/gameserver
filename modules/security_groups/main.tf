resource "aws_security_group" "game_server" {
  name        = var.security_group_name
  description = "Security group for game server"
  vpc_id      = var.vpc_id

  # Minecraft server port
  ingress {
    from_port   = var.game_port
    to_port     = var.game_port
    protocol    = var.game_protocol
    cidr_blocks = var.allowed_game_ips
  }

  # WebSocket port
  ingress {
    from_port   = var.websocket_port
    to_port     = var.websocket_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  # Allow all outbound traffic to VPC endpoints
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    description = "Allow HTTPS to VPC endpoints"
  }

  # Allow outbound internet access for updates and downloads
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow internet access for updates"
  }

  tags = {
    Name = var.security_group_name
  }
}

# Get VPC data
data "aws_vpc" "selected" {
  id = var.vpc_id
}