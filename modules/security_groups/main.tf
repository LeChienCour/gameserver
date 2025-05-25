resource "aws_security_group" "game_server" {
  name        = var.security_group_name
  description = "Security group for game server with WebSocket support"
  vpc_id      = var.vpc_id

  # Game Server Port
  ingress {
    from_port   = var.game_port
    to_port     = var.game_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_game_ips
    description = "Game server port"
  }

  # WebSocket Port
  ingress {
    from_port   = var.websocket_port
    to_port     = var.websocket_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "WebSocket server port"
  }

  # SSH Access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
    description = "SSH access"
  }

  # All Outbound Traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = var.security_group_name
  }
}