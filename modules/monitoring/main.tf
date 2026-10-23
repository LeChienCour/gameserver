# CloudWatch Alarms and Unified Dashboard for Game Server & Voice Pipeline

resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  count               = var.instance_id != null ? 1 : 0
  alarm_name          = "${var.prefix}-ec2-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Triggers when Minecraft EC2 CPU exceeds 85% for 2 minutes"

  dimensions = {
    InstanceId = var.instance_id
  }

  tags = {
    Environment = var.environment
    Stage       = var.stage
  }
}

resource "aws_cloudwatch_metric_alarm" "event_dlq_messages" {
  alarm_name          = "${var.prefix}-eventbridge-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when failed audio events land in the EventBridge SQS DLQ"

  dimensions = {
    QueueName = var.event_dlq_name
  }

  tags = {
    Environment = var.environment
    Stage       = var.stage
  }
}

resource "aws_cloudwatch_metric_alarm" "message_lambda_errors" {
  alarm_name          = "${var.prefix}-message-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Triggers when the WebSocket message Lambda experiences > 5 errors/minute"

  dimensions = {
    FunctionName = var.lambda_function_names["message"]
  }

  tags = {
    Environment = var.environment
    Stage       = var.stage
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.prefix}-observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Duration & Latency (ms)"
          region = var.region
          stat   = "p95"
          period = 60
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["message"]],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["process_audio"]],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["validate_audio"]]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "WebSocket API Gateway Traffic & Errors"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApiGateway", "ConnectCount", "ApiId", var.websocket_api_id],
            ["AWS/ApiGateway", "MessageCount", "ApiId", var.websocket_api_id],
            ["AWS/ApiGateway", "IntegrationError", "ApiId", var.websocket_api_id],
            ["AWS/ApiGateway", "ClientError", "ApiId", var.websocket_api_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title  = "EventBridge DLQ Depth"
          region = var.region
          stat   = "Maximum"
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.event_dlq_name]
          ]
        }
      }
    ]
  })
}
