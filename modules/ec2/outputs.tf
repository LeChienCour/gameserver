# EC2 Instance outputs
output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.game_server.id
}

output "instance_public_ip" {
  description = "The public IP address of the EC2 instance"
  value       = aws_eip.game_server_eip.public_ip
}

output "instance_private_ip" {
  description = "The private IP address of the EC2 instance"
  value       = aws_instance.game_server.private_ip
}

output "instance_role_arn" {
  description = "ARN of the IAM role attached to the instance"
  value       = aws_iam_role.game_server_role.arn
}