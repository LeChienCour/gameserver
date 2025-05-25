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

output "route_ids" {
  description = "Map of WebSocket route IDs"
  value = {
    connect    = aws_apigatewayv2_route.connect.id
    disconnect = aws_apigatewayv2_route.disconnect.id
    sendaudio  = aws_apigatewayv2_route.sendaudio.id
    default    = aws_apigatewayv2_route.default.id
  }
}

output "integration_ids" {
  description = "Map of WebSocket integration IDs"
  value = {
    connect    = aws_apigatewayv2_integration.connect.id
    disconnect = aws_apigatewayv2_integration.disconnect.id
    message    = aws_apigatewayv2_integration.message.id
  }
} 