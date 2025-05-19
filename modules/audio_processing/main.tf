# KMS Key for audio encryption
resource "aws_kms_key" "audio_key" {
  description             = "KMS key for audio encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda function for audio processing
resource "aws_lambda_function" "process_audio" {
  filename         = var.lambda_functions.process_audio
  function_name    = "${var.prefix}-process-audio"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 300
  memory_size     = 1024

  environment {
    variables = {
      AUDIO_BUCKET_NAME = var.audio_bucket_name
      KMS_KEY_ID       = aws_kms_key.audio_key.id
      EVENT_BUS_ARN    = var.event_bus_arn
    }
  }
}

# Lambda function for audio validation
resource "aws_lambda_function" "validate_audio" {
  filename         = var.lambda_functions.validate_audio
  function_name    = "${var.prefix}-validate-audio"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = {
      EVENT_BUS_ARN = var.event_bus_arn
    }
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.prefix}-audio-processing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.prefix}-audio-processing-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.audio_bucket_name}",
          "arn:aws:s3:::${var.audio_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.audio_key.arn
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = var.event_bus_arn
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

# EventBridge Rule for audio processing
resource "aws_cloudwatch_event_rule" "audio_processing_rule" {
  name        = "${var.prefix}-audio-processing-rule"
  description = "Rule for processing audio events"
  event_bus_name = var.event_bus_name

  event_pattern = jsonencode({
    source      = [var.event_source]
    detail-type = ["SendAudioEvent"]
    detail = {
      status = ["PENDING"]
    }
  })
}

# EventBridge Target for audio processing
resource "aws_cloudwatch_event_target" "audio_processing_target" {
  rule           = aws_cloudwatch_event_rule.audio_processing_rule.name
  event_bus_name = var.event_bus_name
  target_id      = "${var.prefix}-audio-processing-target"
  arn            = aws_lambda_function.process_audio.arn
}

# EventBridge Rule for audio validation
resource "aws_cloudwatch_event_rule" "audio_validation_rule" {
  name        = "${var.prefix}-audio-validation-rule"
  description = "Rule for validating audio events"
  event_bus_name = var.event_bus_name

  event_pattern = jsonencode({
    source      = [var.event_source]
    detail-type = ["SendAudioEvent"]
    detail = {
      status = ["PROCESSING"]
    }
  })
}

# EventBridge Target for audio validation
resource "aws_cloudwatch_event_target" "audio_validation_target" {
  rule           = aws_cloudwatch_event_rule.audio_validation_rule.name
  event_bus_name = var.event_bus_name
  target_id      = "${var.prefix}-audio-validation-target"
  arn            = aws_lambda_function.validate_audio.arn
}

# Lambda Permissions for EventBridge
resource "aws_lambda_permission" "process_audio" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_audio.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.audio_processing_rule.arn
}

resource "aws_lambda_permission" "validate_audio" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validate_audio.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.audio_validation_rule.arn
} 