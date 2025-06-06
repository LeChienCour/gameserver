# IAM Role for EC2
resource "aws_iam_role" "game_server_role" {
  name = "game-server-role-${var.stage}"

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

  tags = {
    Name  = "game-server-role-${var.stage}"
    Stage = var.stage
  }
}

# IAM Policy for EC2
resource "aws_iam_role_policy" "game_server_policy" {
  name = "game-server-policy-${var.stage}"
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

# Attach AWS Systems Manager Managed Policy
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.game_server_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "game_server_profile" {
  name = "game-server-profile-${var.stage}"
  role = aws_iam_role.game_server_role.name

  tags = {
    Name  = "game-server-profile-${var.stage}"
    Stage = var.stage
  }
}

# Load user data script
data "template_file" "user_data" {
  template = file("${path.module}/templates/user_data.sh")

  vars = {
    game_port           = var.game_port
    websocket_port      = var.websocket_port
    user_pool_id        = var.user_pool_id
    user_pool_client_id = var.user_pool_client_id
    stage               = var.stage
    environment         = var.environment
  }
}

# EC2 Instance
resource "aws_instance" "game_server" {
  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = true
  key_name                    = var.key_name

  user_data = data.template_file.user_data.rendered

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = {
    Name        = "game-server-${var.stage}"
    Environment = var.environment
    Stage       = var.stage
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
    Name        = "minecraft-server-eip-${var.stage}"
    Environment = var.environment
    Stage       = var.stage
  }
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "minecraft_logs" {
  name              = "/minecraft/server/${var.stage}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "minecraft-logs-${var.stage}"
    Environment = var.environment
    Stage       = var.stage
    Managed_by  = "terraform"
  }
}
