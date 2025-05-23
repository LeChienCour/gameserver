# WebSocket API Gateway
resource "aws_apigatewayv2_api" "websocket" {
  name                       = "${var.prefix}-websocket"
  protocol_type             = "WEBSOCKET"
  route_selection_expression = "$request.body.action"

  tags = {
    Name        = "${var.prefix}-websocket"
    Environment = var.environment
    Service     = "WebSocket"
  }
}

# API Key and Usage Plan for Rate Limiting
resource "aws_api_gateway_api_key" "websocket" {
  name = "${var.prefix}-websocket-key"

  tags = {
    Name        = "${var.prefix}-websocket-key"
    Environment = var.environment
    Service     = "WebSocket"
  }
}

resource "aws_api_gateway_usage_plan" "websocket" {
  name = "${var.prefix}-websocket-usage-plan"

  api_stages {
    api_id = aws_apigatewayv2_api.websocket.id
    stage  = aws_apigatewayv2_stage.websocket.name
  }

  # Monthly quota of 1 million requests
  quota_settings {
    limit  = 1000000
    period = "MONTH"
  }

  # Rate limiting: 50 requests per second with burst of 100
  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  tags = {
    Name        = "${var.prefix}-websocket-usage-plan"
    Environment = var.environment
    Service     = "WebSocket"
  }
}

resource "aws_api_gateway_usage_plan_key" "websocket" {
  key_id        = aws_api_gateway_api_key.websocket.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.websocket.id
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "websocket" {
  name              = "/aws/apigateway/${var.prefix}-websocket"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.prefix}-websocket-logs"
    Environment = var.environment
    Service     = "WebSocket"
  }
}

# WebSocket Stage with Logging and Monitoring
resource "aws_apigatewayv2_stage" "websocket" {
  api_id = aws_apigatewayv2_api.websocket.id
  name   = var.stage_name

  # Detailed access logging configuration
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.websocket.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip            = "$context.identity.sourceIp"
      caller        = "$context.identity.caller"
      user          = "$context.identity.user"
      requestTime   = "$context.requestTime"
      httpMethod    = "$context.httpMethod"
      resourcePath  = "$context.resourcePath"
      status        = "$context.status"
      protocol      = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  # Stage settings for monitoring and throttling
  default_route_settings {
    detailed_metrics_enabled = true
    logging_level           = "INFO"
    data_trace_enabled      = true
    throttling_burst_limit  = 100
    throttling_rate_limit   = 50
  }

  auto_deploy = true

  tags = {
    Name        = "${var.prefix}-websocket-stage"
    Environment = var.environment
    Service     = "WebSocket"
  }
}

# API Gateway Account Settings for CloudWatch Integration
resource "aws_api_gateway_account" "websocket" {
  cloudwatch_role_arn = var.cloudwatch_role_arn
} 