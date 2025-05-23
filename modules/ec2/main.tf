# IAM Role for EC2
resource "aws_iam_role" "game_server_role" {
  name = "game-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for EC2
resource "aws_iam_role_policy" "game_server_policy" {
  name = "game-server-policy"
  role = aws_iam_role.game_server_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:GetUser",
          "cognito-idp:GetUserAttributeVerificationCode",
          "cognito-idp:VerifyUserAttribute",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminInitiateAuth",
          "cognito-idp:AdminRespondToAuthChallenge"
        ]
        Resource = [
          "arn:aws:cognito-idp:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:userpool/${var.user_pool_id}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/game-server/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "game_server_profile" {
  name = "game-server-profile"
  role = aws_iam_role.game_server_role.name
}

# Cargar script de user data
data "template_file" "user_data" {
  template = file("${path.module}/userdata.sh")

  vars = {
    minecraft_version = var.minecraft_version
    neoforge_version = var.neoforge_version
    server_memory = var.server_memory
    java_parameters = var.java_parameters
  }
}

# EC2 Instance
resource "aws_instance" "game_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.game_server_profile.name

  user_data = data.template_file.user_data.rendered
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "minecraft-neoforge-server"
    Environment = var.environment
    Managed_by = "terraform"
  }
}

# Get current region
data "aws_region" "current" {}

# Get current account ID
data "aws_caller_identity" "current" {}

resource "aws_eip" "game_server_eip" {
  instance = aws_instance.game_server.id
  domain   = "vpc"

  tags = {
    Name = "minecraft-server-eip"
    Environment = var.environment
  }
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "minecraft_logs" {
  name              = "/minecraft/server/${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    Managed_by  = "terraform"
  }
}
