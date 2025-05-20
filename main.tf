data "aws_caller_identity" "current" {}

terraform {
  backend "s3" {
    bucket         = "devops-t2-gameserver-tfstate"
    key            = "terraform/state"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# VPC and Network Configuration
module "vpc" {
  source              = "./modules/vpc"
  vpc_cidr            = var.vpc_cidr
  public_subnets_cidr = var.public_subnets_cidr
  availability_zones  = var.availability_zones
  vpc_name            = var.vpc_name
}

# Security Groups for Game Server and WebSocket
module "security_groups" {
  source              = "./modules/security_groups"
  vpc_id              = module.vpc.vpc_id
  game_port           = var.game_port
  websocket_port      = var.websocket_port
  ssh_cidr            = var.ssh_cidr
  security_group_name = var.security_group_name
  allowed_game_ips    = ["0.0.0.0/0"]
  game_protocol       = var.game_protocol
}

# EC2 Game Server with WebSocket Support
module "ec2_game_server" {
  source            = "./modules/ec2"
  ami_id            = var.ami_id
  instance_type     = var.instance_type
  subnet_id         = module.vpc.public_subnets_ids[0]
  security_group_id = module.security_groups.game_server_sg_id
  game_port         = var.game_port
  websocket_port    = var.websocket_port
  user_pool_id      = module.cognito.user_pool_id
  user_pool_client_id = module.cognito.user_pool_client_id
}

# Cognito for Authentication
module "cognito" {
  source          = "./modules/cognito"
  user_pool_name  = var.user_pool_name
  app_client_name = var.app_client_name
  admin_role_name = var.admin_role_name
}

# EventBridge for event handling
module "eventbridge" {
  source = "./modules/eventbridge"
  
  prefix         = var.eventbridge_prefix
  event_bus_name = var.eventbridge_bus_name
  event_source   = var.eventbridge_event_source
  event_detail_type = var.eventbridge_event_detail_type
  log_retention_days = var.eventbridge_log_retention_days
}

# DynamoDB table for WebSocket connections
resource "aws_dynamodb_table" "websocket_connections" {
  name           = "${var.project_name}-connections"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "connectionId"
  
  attribute {
    name = "connectionId"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-connections"
    Environment = var.environment
  }
}

# Create Lambda deployment packages
data "archive_file" "connect_function" {
  type        = "zip"
  source_dir  = "${path.module}/functions/connect"
  output_path = "${path.module}/lambda/connect.zip"
}

data "archive_file" "disconnect_function" {
  type        = "zip"
  source_dir  = "${path.module}/functions/disconnect"
  output_path = "${path.module}/lambda/disconnect.zip"
}

data "archive_file" "message_function" {
  type        = "zip"
  source_dir  = "${path.module}/functions/message"
  output_path = "${path.module}/lambda/message.zip"
}

# WebSocket API Gateway
module "websocket" {
  source = "./modules/websocket"
  
  prefix             = var.websocket_prefix
  stage_name         = var.websocket_stage_name
  environment        = var.environment
  project_name       = var.project_name
  log_retention_days = var.log_retention_days
  event_bus_arn      = module.eventbridge.event_bus_arn
  connections_table  = aws_dynamodb_table.websocket_connections.name
  
  # Lambda functions for WebSocket handling
  lambda_functions = {
    connect    = data.archive_file.connect_function.output_path
    disconnect = data.archive_file.disconnect_function.output_path
    message    = data.archive_file.message_function.output_path
  }

  # Additional IAM permissions
  lambda_environment_variables = {
    CONNECTIONS_TABLE = aws_dynamodb_table.websocket_connections.name
    EVENT_SOURCE     = var.eventbridge_event_source
    EVENT_DETAIL_TYPE = var.eventbridge_event_detail_type
    EVENT_BUS_NAME   = module.eventbridge.event_bus_name
  }

  depends_on = [aws_dynamodb_table.websocket_connections]
}

# SSM Parameters for Configuration
module "ssm" {
  source = "./modules/ssm"
  
  # Cognito Configuration
  user_pool_id     = module.cognito.user_pool_id
  user_pool_client_id = module.cognito.user_pool_client_id
  
  # WebSocket Configuration
  websocket_api_id = module.websocket.websocket_api_id
  websocket_stage_url = module.websocket.websocket_stage_url
}