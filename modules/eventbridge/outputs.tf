output "event_bus_arn" {
  description = "ARN of the custom event bus"
  value       = aws_cloudwatch_event_bus.game_event_bus.arn
}

output "event_bus_name" {
  description = "Name of the custom event bus"
  value       = aws_cloudwatch_event_bus.game_event_bus.name
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.game_event_logs.name
}

output "event_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.game_event_rule.name
}

output "event_source" {
  description = "Source identifier for the events"
  value       = var.event_source
}

output "event_detail_type" {
  description = "Detail type for the events"
  value       = var.event_detail_type
} 