output "api_id" {
  description = "ID of the WebSocket API"
  value       = aws_apigatewayv2_api.websocket.id
}

output "api_endpoint" {
  description = "WebSocket API endpoint"
  value       = aws_apigatewayv2_api.websocket.api_endpoint
}

output "execution_arn" {
  description = "Execution ARN of the WebSocket API"
  value       = aws_apigatewayv2_api.websocket.execution_arn
}

output "stage_arn" {
  description = "ARN of the WebSocket stage"
  value       = "${aws_apigatewayv2_api.websocket.execution_arn}/${aws_apigatewayv2_stage.websocket.name}"
}

output "api_key" {
  description = "API Key for the WebSocket API"
  value       = aws_api_gateway_api_key.websocket.value
  sensitive   = true
} 