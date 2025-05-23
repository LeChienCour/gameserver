# AWS Account Information
output "aws_account_id" {
  description = "The AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# VPC and Network Information
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets_ids
}

# Security Group Information
output "game_server_security_group_id" {
  description = "Security group ID for the game server"
  value       = module.security_groups.game_server_sg_id
}

# EC2 Instance Information
output "game_server_public_ip" {
  description = "Public IP address of the game server"
  value       = module.ec2_game_server.public_ip
}

output "game_server_private_ip" {
  description = "Private IP address of the game server"
  value       = module.ec2_game_server.private_ip
}

# Cognito Information
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client"
  value       = module.cognito.user_pool_client_id
}

output "cognito_admin_role_arn" {
  description = "The ARN of the Cognito Admin Role"
  value       = module.cognito.admin_role_arn
}

# API Gateway Information
output "websocket_api_id" {
  description = "The ID of the WebSocket API"
  value       = module.api_gateway.api_id
}

output "websocket_stage_url" {
  description = "The WebSocket stage URL"
  value       = module.api_gateway.stage_url
}

output "websocket_api_key" {
  description = "The API key for the WebSocket API"
  value       = module.api_gateway.api_key
  sensitive   = true
}

# DynamoDB Information
output "connections_table_name" {
  description = "The name of the DynamoDB table for WebSocket connections"
  value       = aws_dynamodb_table.websocket_connections.name
}

# EventBridge Information
output "event_bus_name" {
  description = "The name of the EventBridge event bus"
  value       = module.eventbridge.event_bus_name
}

output "event_bus_arn" {
  description = "The ARN of the EventBridge event bus"
  value       = module.eventbridge.event_bus_arn
}

output "audio_processing_rule_arn" {
  description = "The ARN of the EventBridge rule for audio processing"
  value       = module.eventbridge.audio_processing_rule_arn
}

output "audio_validation_rule_arn" {
  description = "The ARN of the EventBridge rule for audio validation"
  value       = module.eventbridge.audio_validation_rule_arn
}

# KMS Information
output "kms_key_arn" {
  description = "The ARN of the KMS key"
  value       = module.kms.key_arn
}

output "kms_key_id" {
  description = "The ID of the KMS key"
  value       = module.kms.key_id
}

# Lambda Information
output "process_audio_function_arn" {
  description = "The ARN of the process audio Lambda function"
  value       = module.lambda.process_audio_function_arn
}

output "validate_audio_function_arn" {
  description = "The ARN of the validate audio Lambda function"
  value       = module.lambda.validate_audio_function_arn
}

# IAM Information
output "lambda_role_arn" {
  description = "The ARN of the Lambda IAM role"
  value       = module.iam.lambda_role_arn
}

output "lambda_role_name" {
  description = "The name of the Lambda IAM role"
  value       = module.iam.lambda_role_name
}

output "cloudwatch_role_arn" {
  description = "The ARN of the API Gateway CloudWatch IAM role"
  value       = module.iam.cloudwatch_role_arn
}

# Storage Information
output "audio_bucket_name" {
  description = "The name of the S3 bucket for audio storage"
  value       = aws_s3_bucket.audio_storage.id
}

# Console URLs for AWS Services
output "console_urls" {
  description = "AWS Console URLs for various services"
  value = {
    cloudwatch_logs = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups/log-group/${replace(module.eventbridge.log_group_name, "/", "$252F")}"
    eventbridge     = "https://${var.region}.console.aws.amazon.com/events/home?region=${var.region}#/eventbuses/${var.event_bus_name}"
    cognito         = "https://${var.region}.console.aws.amazon.com/cognito/v2/idp/user-pools/${module.cognito.user_pool_id}/users?region=${var.region}"
    ec2             = "https://${var.region}.console.aws.amazon.com/ec2/v2/home?region=${var.region}#Instances:instanceId=${module.ec2_game_server.instance_id}"
  }
}

# Game Server Connection Information
output "game_server_connection_info" {
  description = "Game server connection information"
  value = {
    instance_id   = module.ec2_game_server.instance_id
    game_port     = var.game_port
    websocket_url = module.api_gateway.stage_url
  }
}