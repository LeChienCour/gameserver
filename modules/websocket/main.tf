# WebSocket API Gateway
resource "aws_apigatewayv2_api" "websocket_api" {
  name                       = "${var.prefix}-websocket-api"
  protocol_type             = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
  
  # Add API key authorization
  api_key_selection_expression = "$request.header.x-api-key"
}

# API Key
resource "aws_api_gateway_api_key" "websocket_key" {
  name = "${var.prefix}-websocket-key"
}

# Usage Plan
resource "aws_api_gateway_usage_plan" "websocket" {
  name = "${var.prefix}-websocket-usage-plan"

  api_stages {
    api_id = aws_apigatewayv2_api.websocket_api.id
    stage  = aws_apigatewayv2_stage.websocket_stage.name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_api_gateway_usage_plan_key" "websocket" {
  key_id        = aws_api_gateway_api_key.websocket_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.websocket.id
}

# IAM Role for API Gateway Logging
resource "aws_iam_role" "apigateway_cloudwatch" {
  name = "${var.prefix}-apigateway-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for API Gateway Logging
resource "aws_iam_role_policy" "apigateway_cloudwatch" {
  name = "${var.prefix}-apigateway-cloudwatch"
  role = aws_iam_role.apigateway_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# API Gateway Account Settings
resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch.arn
}

# CloudWatch Log Group for WebSocket API
resource "aws_cloudwatch_log_group" "websocket_logs" {
  name              = "/aws/websocket/${var.prefix}"
  retention_in_days = var.log_retention_days
}

# WebSocket Stage
resource "aws_apigatewayv2_stage" "websocket_stage" {
  api_id = aws_apigatewayv2_api.websocket_api.id
  name   = var.stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.websocket_logs.arn
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

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
    detailed_metrics_enabled = true
  }

  depends_on = [
    aws_cloudwatch_log_group.websocket_logs,
    aws_api_gateway_account.this
  ]
}

# Lambda Functions
resource "aws_lambda_function" "connect" {
  filename         = var.lambda_functions.connect
  function_name    = "${var.prefix}-connect"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.10"
  timeout         = 30

  environment {
    variables = merge(
      {
        CONNECTIONS_TABLE = var.connections_table
      },
      var.lambda_environment_variables
    )
  }
}

resource "aws_lambda_function" "disconnect" {
  filename         = var.lambda_functions.disconnect
  function_name    = "${var.prefix}-disconnect"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.10"
  timeout         = 30

  environment {
    variables = merge(
      {
        CONNECTIONS_TABLE = var.connections_table
      },
      var.lambda_environment_variables
    )
  }
}

resource "aws_lambda_function" "message" {
  filename         = var.lambda_functions.message
  function_name    = "${var.prefix}-message"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.10"
  timeout         = 30

  environment {
    variables = merge(
      {
        CONNECTIONS_TABLE = var.connections_table,
        EVENT_BUS_NAME = var.event_bus_name,
        EVENT_SOURCE = var.event_source
      },
      var.lambda_environment_variables
    )
  }
}

resource "aws_lambda_function" "audio" {
  filename         = var.lambda_functions.audio
  function_name    = "${var.prefix}-audio"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.10"
  timeout         = 30
  memory_size     = 256

  environment {
    variables = merge(
      {
        CONNECTIONS_TABLE = var.connections_table
        EVENT_BUS_ARN    = var.event_bus_arn
      },
      var.lambda_environment_variables
    )
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/${var.connections_table}"
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = var.event_bus_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${var.audio_bucket_arn}/*"
        ]
      }
    ]
  })
}

# WebSocket Routes
resource "aws_apigatewayv2_route" "connect" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect.id}"
}

resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect.id}"
}

# Route for handling sendaudio action
resource "aws_apigatewayv2_route" "sendaudio" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "sendaudio"
  target    = "integrations/${aws_apigatewayv2_integration.message.id}"
}

# Route for handling audio messages
resource "aws_apigatewayv2_route" "audio" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "audio"
  target    = "integrations/${aws_apigatewayv2_integration.audio.id}"
}

# Default route for any other action
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.message.id}"
}

# WebSocket Integrations
resource "aws_apigatewayv2_integration" "connect" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.connect.invoke_arn
}

resource "aws_apigatewayv2_integration" "disconnect" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.disconnect.invoke_arn
}

resource "aws_apigatewayv2_integration" "message" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.message.invoke_arn
}

resource "aws_apigatewayv2_integration" "audio" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.audio.invoke_arn
}

# Lambda Permissions
resource "aws_lambda_permission" "connect" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.connect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "disconnect" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disconnect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "message" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.message.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "audio" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.audio.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
}

# Lambda permission for default route
resource "aws_lambda_permission" "default" {
  statement_id  = "AllowAPIGatewayInvokeDefault"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.message.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*/*"
} 