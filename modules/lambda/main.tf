# Audio Processing Lambda Functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = toset([
    "${var.prefix}-process-audio",
    "${var.prefix}-validate-audio",
    "${var.prefix}-connect",
    "${var.prefix}-disconnect",
    "${var.prefix}-message",
    "${var.prefix}-authorizer"
  ])

  name              = "/aws/lambda/${each.value}"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    Stage       = var.stage
  }
}

resource "aws_lambda_function" "process_audio" {
  filename         = var.lambda_functions.process_audio
  source_code_hash = fileexists(var.lambda_functions.process_audio) ? filebase64sha256(var.lambda_functions.process_audio) : null
  function_name    = "${var.prefix}-process-audio"
  role             = var.lambda_role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  architectures    = [var.lambda_architecture]
  timeout          = var.process_audio_timeout
  memory_size      = var.process_audio_memory

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
  filename         = var.lambda_functions.validate_audio
  source_code_hash = fileexists(var.lambda_functions.validate_audio) ? filebase64sha256(var.lambda_functions.validate_audio) : null
  function_name    = "${var.prefix}-validate-audio"
  role             = var.lambda_role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  architectures    = [var.lambda_architecture]
  timeout          = var.validate_audio_timeout
  memory_size      = var.validate_audio_memory

  environment {
    variables = {
      CONNECTIONS_TABLE = "${var.project_name}-${var.stage}-connections"
      AUDIO_BUCKET      = var.audio_bucket_name
      EVENT_BUS_NAME    = var.event_bus_name
      EVENT_SOURCE      = var.event_source
      ECHO_MODE         = tostring(var.enable_echo_mode)
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
  filename         = var.lambda_functions.connect
  source_code_hash = fileexists(var.lambda_functions.connect) ? filebase64sha256(var.lambda_functions.connect) : null
  function_name    = "${var.prefix}-connect"
  role             = var.lambda_role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  architectures    = [var.lambda_architecture]
  timeout          = var.websocket_timeout
  memory_size      = var.websocket_memory

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
  filename         = var.lambda_functions.disconnect
  source_code_hash = fileexists(var.lambda_functions.disconnect) ? filebase64sha256(var.lambda_functions.disconnect) : null
  function_name    = "${var.prefix}-disconnect"
  role             = var.lambda_role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  architectures    = [var.lambda_architecture]
  timeout          = var.websocket_timeout
  memory_size      = var.websocket_memory

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
  filename         = var.lambda_functions.message
  source_code_hash = fileexists(var.lambda_functions.message) ? filebase64sha256(var.lambda_functions.message) : null
  function_name    = "${var.prefix}-message"
  role             = var.lambda_role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  architectures    = [var.lambda_architecture]
  timeout          = var.websocket_timeout
  memory_size      = var.websocket_memory

  environment {
    variables = {
      CONNECTIONS_TABLE     = "${var.project_name}-${var.stage}-connections"
      EVENT_BUS_NAME        = var.event_bus_name
      EVENT_SOURCE          = var.event_source
      DIRECT_BROADCAST      = tostring(var.enable_direct_broadcast)
      ENABLE_AUDIO_ARCHIVAL = tostring(var.enable_audio_archival)
      ECHO_MODE             = tostring(var.enable_echo_mode)
      MAX_VOICE_DISTANCE    = tostring(var.max_voice_distance)
    }
  }

  tags = {
    Name        = "${var.prefix}-message"
    Environment = var.environment
    Service     = "WebSocket"
    Stage       = var.stage
  }
}

resource "aws_lambda_function" "authorizer" {
  filename         = lookup(var.lambda_functions, "authorizer", "lambda/authorizer.zip")
  source_code_hash = fileexists(lookup(var.lambda_functions, "authorizer", "lambda/authorizer.zip")) ? filebase64sha256(lookup(var.lambda_functions, "authorizer", "lambda/authorizer.zip")) : null
  function_name    = "${var.prefix}-authorizer"
  role             = var.lambda_role_arn
  handler          = "lambda_function.lambda_handler"
  runtime          = var.lambda_runtime
  architectures    = [var.lambda_architecture]
  timeout          = var.websocket_timeout
  memory_size      = var.websocket_memory

  environment {
    variables = {
      STAGE                 = var.stage
      API_KEY_SSM_PARAMETER = "/game-server/${var.stage}/websocket/api-key"
    }
  }

  tags = {
    Name        = "${var.prefix}-authorizer"
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

resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowAPIGatewayAuthorizerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/authorizers/*"
}
