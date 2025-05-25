# Account Information
output "aws_account_id" {
  description = "The AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# API Gateway Information
output "websocket_api_id" {
  description = "The ID of the WebSocket API"
  value       = module.api_gateway.api_id
}

output "websocket_api_key" {
  description = "The API key for the WebSocket API"
  value       = module.api_gateway.api_key
  sensitive   = true
}

output "websocket_stage_url" {
  description = "The WebSocket stage URL"
  value       = module.api_gateway.api_endpoint
}

output "websocket_execution_arn" {
  description = "The execution ARN of the WebSocket API"
  value       = module.api_gateway.execution_arn
}

output "websocket_route_ids" {
  description = "Map of WebSocket route IDs"
  value       = module.api_gateway.route_ids
}

# Cognito Information
output "cognito_admin_role_arn" {
  description = "The ARN of the Cognito Admin Role"
  value       = module.cognito.cognito_admin_role_arn
}

output "cognito_user_pool_client_id" {
  description = "The ID of the Cognito User Pool Client"
  value       = module.cognito.user_pool_client_id
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = module.cognito.user_pool_id
}

# Console URLs
output "console_urls" {
  description = "AWS Console URLs for various services"
  value = {
    cloudwatch_logs = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups/log-group/${replace(module.eventbridge.log_group_name, "/", "$252F")}"
    cognito         = "https://${var.region}.console.aws.amazon.com/cognito/v2/idp/user-pools/${module.cognito.user_pool_id}/users?region=${var.region}"
    ec2             = "https://${var.region}.console.aws.amazon.com/ec2/v2/home?region=${var.region}#Instances:instanceId=${module.ec2_game_server.instance_id}"
    eventbridge     = "https://${var.region}.console.aws.amazon.com/events/home?region=${var.region}#/eventbuses/${var.event_bus_name}"
  }
}

# DynamoDB Information
output "connections_table_name" {
  description = "The name of the DynamoDB table for WebSocket connections"
  value       = aws_dynamodb_table.websocket_connections.name
}

# EC2 Information
output "game_server_connection_info" {
  description = "Game server connection information"
  value = {
    instance_id   = module.ec2_game_server.instance_id
    game_port     = var.game_port
    websocket_url = module.api_gateway.api_endpoint
  }
}

output "game_server_private_ip" {
  description = "Private IP address of the game server"
  value       = module.ec2_game_server.instance_private_ip
}

output "game_server_public_ip" {
  description = "Public IP address of the game server"
  value       = module.ec2_game_server.game_server_public_ip
}

output "game_server_security_group_id" {
  description = "Security group ID for the game server"
  value       = module.security_groups.game_server_sg_id
}

output "game_server_instance_role_arn" {
  description = "ARN of the IAM role attached to the game server instance"
  value       = module.ec2_game_server.instance_role_arn
}

# EventBridge Information
output "event_bus_arn" {
  description = "The ARN of the EventBridge event bus"
  value       = module.eventbridge.event_bus_arn
}

output "event_bus_name" {
  description = "The name of the EventBridge event bus"
  value       = module.eventbridge.event_bus_name
}

output "event_rules" {
  description = "EventBridge rules information"
  value = {
    audio_processing = {
      arn  = module.eventbridge.audio_processing_rule_arn
      name = module.eventbridge.event_rule_name
    }
    audio_validation = {
      arn = module.eventbridge.audio_validation_rule_arn
    }
  }
}

output "event_log_group_name" {
  description = "Name of the EventBridge CloudWatch log group"
  value       = module.eventbridge.log_group_name
}

# IAM Information
output "cloudwatch_role_arn" {
  description = "The ARN of the API Gateway CloudWatch IAM role"
  value       = module.iam.cloudwatch_role_arn
}

output "lambda_role_arn" {
  description = "The ARN of the Lambda IAM role"
  value       = module.iam.lambda_role_arn
}

output "lambda_role_name" {
  description = "The name of the Lambda IAM role"
  value       = module.iam.lambda_role_name
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

output "kms_alias_arn" {
  description = "The ARN of the KMS key alias"
  value       = module.kms.alias_arn
}

# Lambda Information
output "lambda_functions" {
  description = "Map of Lambda function information"
  value = {
    process_audio = {
      arn  = module.lambda.process_audio_function_arn
      name = module.lambda.lambda_function_names["process_audio"]
    }
    validate_audio = {
      arn  = module.lambda.validate_audio_function_arn
      name = module.lambda.lambda_function_names["validate_audio"]
    }
    connect = {
      name = module.lambda.lambda_function_names["connect"]
    }
    disconnect = {
      name = module.lambda.lambda_function_names["disconnect"]
    }
    message = {
      name = module.lambda.lambda_function_names["message"]
    }
  }
}

# SSM Information
output "ssm_cognito_parameters" {
  description = "SSM Parameters for Cognito"
  value = {
    user_pool_id = {
      arn  = module.ssm.user_pool_id_parameter_arn
      name = module.ssm.user_pool_id_parameter_name
    }
    user_pool_client_id = {
      arn  = module.ssm.user_pool_client_id_parameter_arn
      name = module.ssm.user_pool_client_id_parameter_name
    }
  }
}

output "ssm_websocket_parameters" {
  description = "SSM Parameters for WebSocket"
  value = {
    api_id = {
      arn  = module.ssm.websocket_api_id_parameter_arn
      name = module.ssm.websocket_api_id_parameter_name
    }
    stage_url = {
      arn  = module.ssm.websocket_stage_url_parameter_arn
      name = module.ssm.websocket_stage_url_parameter_name
    }
    api_key = {
      arn  = module.ssm.websocket_api_key_parameter_arn
      name = module.ssm.websocket_api_key_parameter_name
    }
  }
  sensitive = true
}

# Storage Information
output "audio_bucket_name" {
  description = "The name of the S3 bucket for audio storage"
  value       = aws_s3_bucket.audio_storage.id
}

# VPC Information
output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets_ids
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}