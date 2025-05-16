resource "aws_security_group" "game_sg" {
  name        = "game-server-sg"
  description = "Security group for game server"
  vpc_id      = var.vpc_id

  ingress {
    description = "Game server traffic"
    from_port   = var.game_port
    to_port     = var.game_port
    protocol    = var.game_protocol
    cidr_blocks = var.allowed_game_ips
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "Audio chat"
    from_port   = var.audio_port
    to_port     = var.audio_port
    protocol    = "udp"
    cidr_blocks = var.allowed_audio_ips
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = var.security_group_name
    Project = "GameServer"
    Owner   = "DevOps Team"
  }
}