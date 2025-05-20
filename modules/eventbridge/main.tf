# EventBridge module for game events

# Create a custom event bus for game events
resource "aws_cloudwatch_event_bus" "game_event_bus" {
  name = var.event_bus_name
}

# Create CloudWatch Log Group for game events
resource "aws_cloudwatch_log_group" "game_event_logs" {
  name              = "/${var.prefix}/events"
  retention_in_days = var.log_retention_days
}

# Create EventBridge rule to capture game events
resource "aws_cloudwatch_event_rule" "game_event_rule" {
  name          = "${var.prefix}-event-rule"
  description   = "Capture game events"
  event_bus_name = aws_cloudwatch_event_bus.game_event_bus.name

  event_pattern = jsonencode({
    source      = [var.event_source]
    detail-type = [var.event_detail_type]
  })
}

# Create EventBridge target to send events to CloudWatch Logs
resource "aws_cloudwatch_event_target" "log_target" {
  rule           = aws_cloudwatch_event_rule.game_event_rule.name
  event_bus_name = aws_cloudwatch_event_bus.game_event_bus.name
  target_id      = "${var.prefix}LogTarget"
  arn            = aws_cloudwatch_log_group.game_event_logs.arn
} 