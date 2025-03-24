terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0" # Puedes ajustar la versión según tus necesidades
    }
  }
}

provider "aws" {
  region = "us-east-1" # Reemplaza con la región que estés utilizando
}

module "vpc" {
  source               = "./modules/vpc"
  vpc_cidr             = var.vpc_cidr
  public_subnets_cidr  = var.public_subnets_cidr
  availability_zones   = var.availability_zones
  vpc_name             = var.vpc_name
}

module "security_groups" {
  source      = "./modules/security_groups"
  vpc_id      = module.vpc.vpc_id
  game_port   = var.game_port
  ssh_cidr    = var.ssh_cidr
  audio_port  = var.audio_port
  game_protocol = var.game_protocol
}

module "ec2_game_server" {
  source            = "./modules/ec2_game_server"
  ami_id            = var.ami_id
  instance_type     = var.instance_type
  subnet_id         = module.vpc.public_subnets_ids[0]
  security_group_id = module.security_groups.game_server_sg_id
  game_port         = var.game_port
}

module "cognito" {
  source = "./modules/cognito"
  user_pool_name = var.user_pool_name
  app_client_name = var.app_client_name
  admin_role_name = var.admin_role_name
}