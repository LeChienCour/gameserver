output "websocket_api_id" {
  description = "ID of the WebSocket API"
  value       = aws_apigatewayv2_api.websocket_api.id
}

output "websocket_api_endpoint" {
  description = "WebSocket API endpoint"
  value       = aws_apigatewayv2_api.websocket_api.api_endpoint
}

output "websocket_stage_url" {
  description = "WebSocket stage URL"
  value       = "${aws_apigatewayv2_api.websocket_api.api_endpoint}/${aws_apigatewayv2_stage.websocket_stage.name}"
}

output "connections_table_name" {
  description = "Name of the DynamoDB table for WebSocket connections"
  value       = var.connections_table
}

output "lambda_functions" {
  description = "Map of Lambda function ARNs"
  value = {
    connect    = aws_lambda_function.connect.arn
    disconnect = aws_lambda_function.disconnect.arn
    message    = aws_lambda_function.message.arn
  }
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.websocket_logs.name
}

output "api_key" {
  description = "API key for WebSocket API authentication"
  value       = aws_api_gateway_api_key.websocket_key.value
  sensitive   = true
} 