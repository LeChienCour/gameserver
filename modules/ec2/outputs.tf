output "game_server_public_ip" {
  value = aws_eip.game_server_eip.public_ip
}

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.game_server.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.game_server.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance"
  value       = aws_instance.game_server.private_ip
}

output "instance_role_arn" {
  description = "ARN of the IAM role attached to the instance"
  value       = aws_iam_role.game_server_role.arn
}