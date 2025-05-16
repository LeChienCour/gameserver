data "aws_caller_identity" "current" {}

terraform {
  backend "s3" {
    bucket         = "devops-t2-gameserver-tfstate"
    key            = "terraform/state"
    region         = "us-east-1"
    encrypt        = true
    use_lockfile   = true
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

module "vpc" {
  source              = "./modules/vpc"
  vpc_cidr            = var.vpc_cidr
  public_subnets_cidr = var.public_subnets_cidr
  availability_zones  = var.availability_zones
  vpc_name            = var.vpc_name
}

module "security_groups" {
  source              = "./modules/security_groups"
  vpc_id              = module.vpc.vpc_id
  game_port           = var.game_port
  ssh_cidr            = var.ssh_cidr
  audio_port          = var.audio_port
  game_protocol       = var.game_protocol
  security_group_name = var.security_group_name
  allowed_game_ips    = ["0.0.0.0/0"]
  allowed_audio_ips   = ["0.0.0.0/0"]
}

module "ec2_game_server" {
  source            = "./modules/ec2"
  ami_id            = var.ami_id
  instance_type     = var.instance_type
  subnet_id         = module.vpc.public_subnets_ids[0]
  security_group_id = module.security_groups.game_server_sg_id
  game_port         = var.game_port
}

module "cognito" {
  source          = "./modules/cognito"
  user_pool_name  = var.user_pool_name
  app_client_name = var.app_client_name
  admin_role_name = var.admin_role_name
}

module "appsync" {
  source       = "./modules/appsync"
  user_pool_id = module.cognito.user_pool_id
  region       = var.region
}