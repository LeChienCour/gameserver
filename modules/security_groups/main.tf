resource "aws_security_group" "game_server" {
  name        = "${var.security_group_name}-${var.stage}"
  description = "Security group for game server - ${var.stage}"
  vpc_id      = var.vpc_id

  # Minecraft server port (TCP)
  ingress {
    description = "Minecraft Game Server TCP"
    from_port   = var.game_port
    to_port     = var.game_port
    protocol    = var.game_protocol
    cidr_blocks = var.allowed_game_ips
  }

  # Optional UDP on game port for query/voice extensions
  ingress {
    description = "Minecraft Game Server UDP"
    from_port   = var.game_port
    to_port     = var.game_port
    protocol    = "udp"
    cidr_blocks = var.allowed_game_ips
  }

  # WebSocket port
  ingress {
    description = "WebSocket TCP"
    from_port   = var.websocket_port
    to_port     = var.websocket_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_game_ips
  }

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.security_group_name}-${var.stage}"
    Stage       = var.stage
    Environment = var.environment
  }
}

# Get VPC data
data "aws_vpc" "selected" {
  id = var.vpc_id
}
