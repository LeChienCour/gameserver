output "aws_account_id" {
  description = "The AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets_ids
}

# Security Group Outputs
output "game_server_sg_id" {
  description = "ID of the game server security group"
  value       = module.security_groups.game_server_sg_id
}

# EC2 Instance Outputs
output "game_server_public_ip" {
  description = "Public IP of the EC2 game server"
  value       = module.ec2_game_server.game_server_public_ip
}

output "game_server_public_dns" {
  description = "Public DNS of the EC2 game server"
  value       = module.ec2_game_server.instance_public_ip
}

# Cognito Outputs
output "user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = module.cognito.user_pool_id
}

output "user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = module.cognito.user_pool_client_id
}

output "cognito_admin_role_arn" {
  description = "ARN of the Cognito admin role"
  value       = module.cognito.cognito_admin_role_arn
}

# WebSocket Outputs
output "websocket_api_id" {
  description = "ID of the WebSocket API"
  value       = module.websocket.websocket_api_id
}

output "websocket_endpoint" {
  description = "WebSocket endpoint URL"
  value       = module.websocket.websocket_endpoint
}

output "websocket_stage_url" {
  description = "URL of the WebSocket API stage"
  value       = module.websocket.websocket_stage_url
}

output "websocket_api_key" {
  description = "API key for WebSocket API authentication"
  value       = module.websocket.api_key
  sensitive   = true
}

# DynamoDB Outputs
output "connections_table_name" {
  description = "Name of the DynamoDB table for WebSocket connections"
  value       = aws_dynamodb_table.websocket_connections.name
}

# EventBridge Outputs
output "event_bus_name" {
  description = "Name of the EventBridge event bus"
  value       = module.eventbridge.event_bus_name
}

output "event_bus_arn" {
  description = "ARN of the EventBridge event bus"
  value       = module.eventbridge.event_bus_arn
}

# SSM Parameter Outputs
output "ssm_user_pool_id_parameter" {
  description = "SSM parameter name for Cognito User Pool ID"
  value       = module.ssm.user_pool_id_parameter_name
}

output "ssm_user_pool_client_id_parameter" {
  description = "SSM parameter name for Cognito User Pool Client ID"
  value       = module.ssm.user_pool_client_id_parameter_name
}

output "ssm_websocket_api_id_parameter" {
  description = "SSM parameter name for WebSocket API ID"
  value       = module.ssm.websocket_api_id_parameter_name
}

output "ssm_websocket_stage_url_parameter" {
  description = "SSM parameter name for WebSocket Stage URL"
  value       = module.ssm.websocket_stage_url_parameter_name
}

output "ssm_websocket_api_key_parameter" {
  description = "SSM parameter name for WebSocket API Key"
  value       = module.ssm.websocket_api_key_parameter_name
  sensitive   = true
}

# Configuration Details
output "eventbridge_configuration" {
  description = "Complete EventBridge configuration for reference"
  value = {
    event_bus_name     = var.eventbridge_bus_name
    event_source       = var.eventbridge_event_source
    event_detail_type  = var.eventbridge_event_detail_type
    log_retention_days = var.eventbridge_log_retention_days
    prefix             = var.eventbridge_prefix
  }
}

# Console URLs
output "cloudwatch_logs_url" {
  description = "CloudWatch Logs URL for monitoring game events"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups/log-group/${replace(module.eventbridge.log_group_name, "/", "$252F")}"
}

output "eventbridge_console_url" {
  description = "EventBridge Console URL for monitoring events"
  value       = "https://${var.region}.console.aws.amazon.com/events/home?region=${var.region}#/eventbuses/${var.eventbridge_bus_name}"
}

output "cognito_console_url" {
  description = "Cognito Console URL for user pool management"
  value       = "https://${var.region}.console.aws.amazon.com/cognito/v2/idp/user-pools/${module.cognito.user_pool_id}/users?region=${var.region}"
}

output "ec2_console_url" {
  description = "EC2 Console URL for game server instance"
  value       = "https://${var.region}.console.aws.amazon.com/ec2/v2/home?region=${var.region}#Instances:instanceId=${module.ec2_game_server.instance_id}"
}

# Connection Information
output "game_server_connection_info" {
  description = "Game server connection information"
  value = {
    instance_id   = module.ec2_game_server.instance_id
    game_port     = var.game_port
    websocket_url = module.websocket.websocket_stage_url
  }
}