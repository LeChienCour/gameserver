# Provider and Backend Configuration
terraform {
  backend "s3" {
    bucket         = "devops-t2-gameserver-tfstate"
    key            = "terraform.tfstate"
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

# Get key pair name from SSM parameter
data "aws_ssm_parameter" "key_pair" {
  name = "/gameserver/ec2/key_pair"
}

# Find latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# API Gateway Module
module "api_gateway" {
  source = "./modules/api_gateway"

  prefix              = "${var.prefix}-${var.stage}"
  stage_name          = var.websocket_stage_name
  cloudwatch_role_arn = module.iam.cloudwatch_role_arn
  environment         = var.environment

  # Lambda ARNs
  lambda_connect_arn    = module.lambda.lambda_functions["connect"]
  lambda_disconnect_arn = module.lambda.lambda_functions["disconnect"]
  lambda_message_arn    = module.lambda.lambda_functions["message"]

  # VPC Endpoint Configuration
  vpc_endpoint_id = module.vpc.vpc_endpoint_execute_api_id
  vpc_id          = module.vpc.vpc_id
  security_groups = [module.vpc.vpc_endpoints_security_group_id]
  subnet_ids      = module.vpc.public_subnets_ids

  depends_on = [
    module.vpc
  ]
}

# Cognito Module
module "cognito" {
  source          = "./modules/cognito"
  user_pool_name  = var.user_pool_name
  app_client_name = var.app_client_name
  admin_role_name = var.admin_role_name
  stage           = var.stage
}

# DynamoDB Resources
resource "aws_dynamodb_table" "websocket_connections" {
  name         = "${var.project_name}-${var.stage}-connections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connectionId"

  attribute {
    name = "connectionId"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-${var.stage}-connections"
    Environment = var.environment
    Stage       = var.stage
  }
}

# EC2 Module
module "ec2_game_server" {
  source              = "./modules/ec2"
  ami_id              = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux_2.id
  instance_type       = var.instance_type
  subnet_id           = module.vpc.public_subnets_ids[0]
  security_group_id   = module.security_groups.game_server_sg_id
  game_port           = var.game_port
  websocket_port      = var.websocket_port
  user_pool_id        = module.cognito.user_pool_id
  user_pool_client_id = module.cognito.user_pool_client_id
  key_name            = data.aws_ssm_parameter.key_pair.value
  stage               = var.stage
  environment         = var.environment
}

# EventBridge Module
module "eventbridge" {
  source = "./modules/eventbridge"

  prefix             = "${var.prefix}-${var.stage}"
  event_bus_name     = "${var.event_bus_name}-${var.stage}"
  event_source       = var.event_source
  event_detail_type  = var.event_detail_type
  log_retention_days = var.log_retention_days

  # Lambda function ARNs for targets
  process_audio_function_arn  = module.lambda.process_audio_function_arn
  validate_audio_function_arn = module.lambda.validate_audio_function_arn
}

# IAM Module
module "iam" {
  source = "./modules/iam"

  prefix            = "${var.prefix}-${var.stage}"
  audio_bucket_name = aws_s3_bucket.audio_storage.id
  event_bus_arn     = module.eventbridge.event_bus_arn
  connections_table = var.connections_table
  environment       = var.environment
  stage             = var.stage

  depends_on = [
    aws_s3_bucket.audio_storage
  ]
}

# Lambda Module
module "lambda" {
  source = "./modules/lambda"

  prefix                    = "${var.prefix}-${var.stage}"
  lambda_functions          = var.lambda_functions
  audio_bucket_name         = aws_s3_bucket.audio_storage.id
  connections_table         = "${var.connections_table}-${var.stage}"
  audio_processing_rule_arn = module.eventbridge.audio_processing_rule_arn
  audio_validation_rule_arn = module.eventbridge.audio_validation_rule_arn
  lambda_role_arn           = module.iam.lambda_role_arn
  event_bus_name            = module.eventbridge.event_bus_name
  event_source              = var.event_source
  api_gateway_id            = module.api_gateway.api_id
  api_gateway_execution_arn = module.api_gateway.execution_arn
  environment               = var.environment
  stage                     = var.stage

  depends_on = [
    aws_s3_bucket.audio_storage,
    aws_s3_bucket_versioning.audio_storage,
    aws_s3_bucket_server_side_encryption_configuration.audio_storage
  ]
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
  source                          = "./modules/security_groups"
  vpc_id                          = module.vpc.vpc_id
  game_port                       = var.game_port
  websocket_port                  = var.websocket_port
  ssh_cidr                        = var.ssh_cidr
  security_group_name             = var.security_group_name
  allowed_game_ips                = ["0.0.0.0/0"]
  game_protocol                   = var.game_protocol
  vpc_endpoints_security_group_id = module.vpc.vpc_endpoints_security_group_id
  stage                           = var.stage
  environment                     = var.environment
}

# Storage Resources
resource "aws_s3_bucket" "audio_storage" {
  bucket = "${var.audio_bucket_name}-${var.stage}"

  tags = {
    Name        = "${var.project_name}-${var.stage}-audio-storage"
    Environment = var.environment
    Stage       = var.stage
  }
}

# Enable versioning for the S3 bucket
resource "aws_s3_bucket_versioning" "audio_storage" {
  bucket = aws_s3_bucket.audio_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption for the S3 bucket using AWS managed keys
resource "aws_s3_bucket_server_side_encryption_configuration" "audio_storage" {
  bucket = aws_s3_bucket.audio_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "audio_storage" {
  bucket = aws_s3_bucket.audio_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# VPC Module
module "vpc" {
  source              = "./modules/vpc"
  vpc_cidr            = var.vpc_cidr
  public_subnets_cidr = var.public_subnets_cidr
  availability_zones  = var.availability_zones
  vpc_name            = var.vpc_name
  stage               = var.stage
}

# SSM Module
module "ssm" {
  source = "./modules/ssm"

  stage               = var.stage
  user_pool_id        = module.cognito.user_pool_id
  user_pool_client_id = module.cognito.user_pool_client_id
  websocket_api_id    = module.api_gateway.api_id
  websocket_stage_url = module.api_gateway.api_endpoint
  websocket_api_key   = module.api_gateway.api_key
}