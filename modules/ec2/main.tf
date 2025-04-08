resource "aws_instance" "game_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              #Colocar aqui la configuración del servidor del juego
              EOF

  tags = {
    Name = "game-server-instance"
  }
}

resource "aws_eip" "game_server_eip" {
  instance = aws_instance.game_server.id
  domain   = "vpc"

  tags = {
    Name = "game-server-eip"
  }
}
