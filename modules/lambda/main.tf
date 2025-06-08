# Audio Processing Lambda Functions
resource "aws_lambda_function" "process_audio" {
  filename      = var.lambda_functions.process_audio
  function_name = "${var.prefix}-process-audio"
  role          = var.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  timeout       = var.process_audio_timeout
  memory_size   = var.process_audio_memory

  environment {
    variables = {
      AUDIO_BUCKET   = var.audio_bucket_name
      EVENT_BUS_NAME = var.event_bus_name
      EVENT_SOURCE   = var.event_source
    }
  }

  tags = {
    Name        = "${var.prefix}-process-audio"
    Environment = var.environment
    Service     = "AudioProcessing"
    Stage       = var.stage
  }
}

resource "aws_lambda_function" "validate_audio" {
  filename      = var.lambda_functions.validate_audio
  function_name = "${var.prefix}-validate-audio"
  role          = var.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  timeout       = var.validate_audio_timeout
  memory_size   = var.validate_audio_memory

  environment {
    variables = {
      CONNECTIONS_TABLE = "${var.project_name}-${var.stage}-connections"
      EVENT_BUS_NAME    = var.event_bus_name
      EVENT_SOURCE      = var.event_source
    }
  }

  tags = {
    Name        = "${var.prefix}-validate-audio"
    Environment = var.environment
    Service     = "AudioValidation"
    Stage       = var.stage
  }
}

# WebSocket Connection Management Lambda Functions
resource "aws_lambda_function" "connect" {
  filename      = var.lambda_functions.connect
  function_name = "${var.prefix}-connect"
  role          = var.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  timeout       = var.websocket_timeout
  memory_size   = var.websocket_memory

  environment {
    variables = {
      CONNECTIONS_TABLE = "${var.project_name}-${var.stage}-connections"
    }
  }

  tags = {
    Name        = "${var.prefix}-connect"
    Environment = var.environment
    Service     = "WebSocket"
    Stage       = var.stage
  }
}

resource "aws_lambda_function" "disconnect" {
  filename      = var.lambda_functions.disconnect
  function_name = "${var.prefix}-disconnect"
  role          = var.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  timeout       = var.websocket_timeout
  memory_size   = var.websocket_memory

  environment {
    variables = {
      CONNECTIONS_TABLE = "${var.project_name}-${var.stage}-connections"
    }
  }

  tags = {
    Name        = "${var.prefix}-disconnect"
    Environment = var.environment
    Service     = "WebSocket"
    Stage       = var.stage
  }
}

resource "aws_lambda_function" "message" {
  filename      = var.lambda_functions.message
  function_name = "${var.prefix}-message"
  role          = var.lambda_role_arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  timeout       = var.websocket_timeout
  memory_size   = var.websocket_memory

  environment {
    variables = {
      CONNECTIONS_TABLE = "${var.project_name}-${var.stage}-connections"
      EVENT_BUS_NAME    = var.event_bus_name
      EVENT_SOURCE      = var.event_source
    }
  }

  tags = {
    Name        = "${var.prefix}-message"
    Environment = var.environment
    Service     = "WebSocket"
    Stage       = var.stage
  }
}

# Lambda Permissions for EventBridge Integration
resource "aws_lambda_permission" "process_audio" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_audio.function_name
  principal     = "events.amazonaws.com"
  source_arn    = var.audio_processing_rule_arn
}

resource "aws_lambda_permission" "validate_audio" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validate_audio.function_name
  principal     = "events.amazonaws.com"
  source_arn    = var.audio_validation_rule_arn
}

# Lambda Permissions for API Gateway Integration
resource "aws_lambda_permission" "connect" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.connect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_lambda_permission" "disconnect" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disconnect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

resource "aws_lambda_permission" "message" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.message.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
} 