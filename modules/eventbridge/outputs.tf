output "event_bus_arn" {
  description = "ARN of the custom event bus"
  value       = aws_cloudwatch_event_bus.voice_chat_bus.arn
}

output "event_bus_name" {
  description = "Name of the custom event bus"
  value       = aws_cloudwatch_event_bus.voice_chat_bus.name
}

output "eventbridge_role_arn" {
  description = "ARN of the IAM role for EventBridge integration"
  value       = aws_iam_role.appsync_eventbridge_role.arn
}

output "eventbridge_datasource_name" {
  description = "Name of the EventBridge data source in AppSync"
  value       = aws_appsync_datasource.eventbridge_datasource.name
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.voice_chat_logs.name
}

output "event_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.voice_chat_event_rule.name
}

output "event_source" {
  description = "Source identifier for the events"
  value       = var.event_source
}

output "event_detail_type" {
  description = "Detail type for the events"
  value       = var.event_detail_type
} 