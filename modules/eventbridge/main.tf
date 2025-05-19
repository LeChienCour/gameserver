# EventBridge module for Voice Chat functionality

# Create a custom event bus for voice chat events
resource "aws_cloudwatch_event_bus" "voice_chat_bus" {
  name = var.event_bus_name
}

# Create IAM role for AppSync to publish events to EventBridge
resource "aws_iam_role" "appsync_eventbridge_role" {
  name = "${var.prefix}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
      }
    ]
  })
}

# Create IAM policy for AppSync to publish events to EventBridge
resource "aws_iam_role_policy" "appsync_eventbridge_policy" {
  name = "${var.prefix}-eventbridge-policy"
  role = aws_iam_role.appsync_eventbridge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = [
          aws_cloudwatch_event_bus.voice_chat_bus.arn
        ]
      }
    ]
  })
}

# Create EventBridge data source in AppSync
resource "aws_appsync_datasource" "eventbridge_datasource" {
  api_id           = var.appsync_api_id
  name             = "${var.prefix}_eventbridge_datasource"
  service_role_arn = aws_iam_role.appsync_eventbridge_role.arn
  type             = "EVENT_BRIDGE"

  event_bridge_config {
    event_bus_arn = aws_cloudwatch_event_bus.voice_chat_bus.arn
  }
}

# Create CloudWatch Log Group for voice chat events
resource "aws_cloudwatch_log_group" "voice_chat_logs" {
  name              = "/${var.prefix}/events"
  retention_in_days = var.log_retention_days
}

# Create EventBridge rule to capture voice chat events
resource "aws_cloudwatch_event_rule" "voice_chat_event_rule" {
  name          = "${var.prefix}-event-rule"
  description   = "Capture voice chat events from AppSync"
  event_bus_name = aws_cloudwatch_event_bus.voice_chat_bus.name

  event_pattern = jsonencode({
    source      = [var.event_source]
    detail-type = [var.event_detail_type]
  })
}

# Create EventBridge target to send events to CloudWatch Logs
resource "aws_cloudwatch_event_target" "log_target" {
  rule           = aws_cloudwatch_event_rule.voice_chat_event_rule.name
  event_bus_name = aws_cloudwatch_event_bus.voice_chat_bus.name
  target_id      = "${var.prefix}LogTarget"
  arn            = aws_cloudwatch_log_group.voice_chat_logs.arn
} 