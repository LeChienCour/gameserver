output "game_server_public_ip" {
  value = aws_eip.game_server_eip.public_ip
}