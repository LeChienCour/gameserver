resource "aws_security_group" "game_sg" {
  name        = "game-server-sg"
  description = "Security group for game server"
  vpc_id      = var.vpc_id

  ingress {
    description = "Game server traffic"
    from_port   = var.game_port
    to_port     = var.game_port
    protocol    = var.game_protocol
    cidr_blocks = ["0.0.0.0/0"] # Permite el tráfico desde cualquier IP
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr] # Limita el acceso SSH a tu IP o rango de IP
  }

  ingress {
    description = "Audio chat"
    from_port   = var.audio_port
    to_port     = var.audio_port
    protocol    = "udp" # Usamos UDP para audio
    cidr_blocks = ["0.0.0.0/0"] # Permite el tráfico desde cualquier IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "game-server-sg"
  }
}

output "game_server_sg_id" {
  value = aws_security_group.game_server.id
}