output "appsync_graphql_api_id" {
  description = "The ID of the AppSync GraphQL API"
  value       = module.appsync.graphql_api_id
}

output "appsync_graphql_api_uri" {
  description = "The URI of the AppSync GraphQL API (HTTPS endpoint)"
  value       = module.appsync.graphql_api_uri
}

output "appsync_api_key_value" {
  description = "The value of the AppSync API Key for initial testing"
  value       = module.appsync.api_key_value
  sensitive   = true
}

output "appsync_api_region" {
  description = "The AWS region where the AppSync API is deployed"
  value       = var.region
}

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
  description = "Name of the EventBridge rule for voice chat events"
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

output "appsync_eventbridge_integration" {
  description = "AppSync and EventBridge integration details"
  value = {
    api_id                = module.appsync.graphql_api_id
    api_uri              = module.appsync.graphql_api_uri
    event_bus_arn        = module.eventbridge.event_bus_arn
    event_bus_name       = module.eventbridge.event_bus_name
    event_source         = var.eventbridge_event_source
    event_detail_type    = var.eventbridge_event_detail_type
    log_group_name       = module.eventbridge.log_group_name
    event_rule_name      = module.eventbridge.event_rule_name
  }
}

output "voice_chat_mutation_details" {
  description = "Details about the sendAudio mutation for voice chat"
  value = {
    mutation_name = "sendAudio"
    arguments = {
      channel    = "String! (required)"
      format     = "String! (required)"
      encoding   = "String! (required)"
      data       = "String! (required)"
      author     = "String! (required)"
      timestamp  = "String! (required)"
      method     = "String! (required)"
    }
    event_details = {
      source      = var.eventbridge_event_source
      detail_type = var.eventbridge_event_detail_type
    }
  }
}

output "cloudwatch_logs_url" {
  description = "CloudWatch Logs URL for monitoring voice chat events"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups/log-group/${replace(module.eventbridge.log_group_name, "/", "$252F")}"
}

output "eventbridge_console_url" {
  description = "EventBridge Console URL for monitoring events"
  value       = "https://${var.region}.console.aws.amazon.com/events/home?region=${var.region}#/eventbuses/${var.eventbridge_bus_name}"
}

output "appsync_console_url" {
  description = "AppSync Console URL for API management"
  value       = "https://${var.region}.console.aws.amazon.com/appsync/home?region=${var.region}#/apis/${module.appsync.graphql_api_id}"
}