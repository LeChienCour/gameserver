output "aws_account_id" {
  description = "The AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# EventBridge outputs
output "eventbridge_bus_arn" {
  description = "ARN of the custom EventBridge event bus"
  value       = module.eventbridge.event_bus_arn
}

output "eventbridge_bus_name" {
  description = "Name of the custom EventBridge event bus"
  value       = module.eventbridge.event_bus_name
}

output "eventbridge_log_group_name" {
  description = "Name of the CloudWatch log group for EventBridge events"
  value       = module.eventbridge.log_group_name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for game events"
  value       = module.eventbridge.event_rule_name
}

# Additional developer-friendly outputs
output "eventbridge_configuration" {
  description = "Complete EventBridge configuration for reference"
  value = {
    event_bus_name     = var.eventbridge_bus_name
    event_source       = var.eventbridge_event_source
    event_detail_type  = var.eventbridge_event_detail_type
    log_retention_days = var.eventbridge_log_retention_days
    prefix             = var.eventbridge_prefix
  }
}

output "cloudwatch_logs_url" {
  description = "CloudWatch Logs URL for monitoring game events"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups/log-group/${replace(module.eventbridge.log_group_name, "/", "$252F")}"
}

output "eventbridge_console_url" {
  description = "EventBridge Console URL for monitoring events"
  value       = "https://${var.region}.console.aws.amazon.com/events/home?region=${var.region}#/eventbuses/${var.eventbridge_bus_name}"
}