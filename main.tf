# Provider and Backend Configuration
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

# Data Sources
data "aws_caller_identity" "current" {}

# API Gateway Module
module "api_gateway" {
  source = "./modules/api_gateway"

  prefix              = var.prefix
  stage_name          = var.websocket_stage_name
  cloudwatch_role_arn = module.iam.cloudwatch_role_arn
  
  # Lambda ARNs
  lambda_connect_arn    = module.lambda.lambda_functions["connect"]
  lambda_disconnect_arn = module.lambda.lambda_functions["disconnect"]
  lambda_message_arn    = module.lambda.lambda_functions["message"]
}

# Cognito Module
module "cognito" {
  source          = "./modules/cognito"
  user_pool_name  = var.user_pool_name
  app_client_name = var.app_client_name
  admin_role_name = var.admin_role_name
}

# DynamoDB Resources
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

# EC2 Module
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

# EventBridge Module
module "eventbridge" {
  source = "./modules/eventbridge"

  prefix            = var.prefix
  event_bus_name    = var.event_bus_name
  event_source      = var.event_source
  event_detail_type = var.event_detail_type
  log_retention_days = var.log_retention_days
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  prefix            = var.prefix
  audio_bucket_name = var.audio_bucket_name
  kms_key_arn       = module.kms.key_arn
  event_bus_arn     = module.eventbridge.event_bus_arn
  connections_table = var.connections_table
}

# KMS Module
module "kms" {
  source = "./modules/kms"

  prefix       = var.prefix
  environment  = var.environment
  project_name = var.project_name
}

# Lambda Module
module "lambda" {
  source = "./modules/lambda"

  prefix            = var.prefix
  lambda_functions  = var.lambda_functions
  audio_bucket_name = var.audio_bucket_name
  kms_key_id        = module.kms.key_id
  event_bus_arn     = module.eventbridge.event_bus_arn
  connections_table = var.connections_table
  enable_echo_mode  = var.enable_echo_mode
  event_rule_arn    = module.eventbridge.audio_processing_rule_arn
  lambda_role_arn   = module.iam.lambda_role_arn
  event_bus_name    = module.eventbridge.event_bus_name
  event_source      = var.event_source
  api_gateway_id    = module.api_gateway.api_id
  api_gateway_execution_arn = module.api_gateway.execution_arn
}

# Lambda Deployment Packages
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

data "archive_file" "process_audio_function" {
  type        = "zip"
  source_dir  = "${path.module}/functions/process_audio"
  output_path = "${path.module}/lambda/process_audio.zip"
}

data "archive_file" "validate_audio_function" {
  type        = "zip"
  source_dir  = "${path.module}/functions/validate_audio"
  output_path = "${path.module}/lambda/validate_audio.zip"
}

# Security Groups Module
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

# Storage Resources
resource "aws_s3_bucket" "audio_storage" {
  bucket = "${var.project_name}-audio-storage-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project_name}-audio-storage"
    Environment = var.environment
  }
}

# VPC Module
module "vpc" {
  source              = "./modules/vpc"
  vpc_cidr            = var.vpc_cidr
  public_subnets_cidr = var.public_subnets_cidr
  availability_zones  = var.availability_zones
  vpc_name            = var.vpc_name
}