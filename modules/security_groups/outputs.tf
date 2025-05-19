output "game_server_sg_id" {
  description = "ID of the game server security group"
  value       = aws_security_group.game_server.id
}

output "game_server_sg_name" {
  description = "Name of the game server security group"
  value       = aws_security_group.game_server.name
}