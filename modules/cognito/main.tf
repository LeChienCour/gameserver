resource "aws_cognito_user_pool" "pool" {
  name = "${var.user_pool_name}-${var.stage}"

  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  verification_message_template {
    email_message = "Your verification code is {####}"
    email_subject = "Your verification code"
  }

  tags = {
    Name  = "${var.user_pool_name}-${var.stage}"
    Stage = var.stage
  }
}

resource "aws_cognito_user_pool" "main" {
  name = var.user_pool_name
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${var.app_client_name}-${var.stage}"
  user_pool_id = aws_cognito_user_pool.pool.id

  tags = {
    Name  = "${var.app_client_name}-${var.stage}"
    Stage = var.stage
  }
}

resource "aws_iam_role" "admin_role" {
  name = "${var.admin_role_name}-${var.stage}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name  = "${var.admin_role_name}-${var.stage}"
    Stage = var.stage
  }
}