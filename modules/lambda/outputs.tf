output "process_audio_function_arn" {
  description = "ARN of the process audio Lambda function"
  value       = aws_lambda_function.process_audio.arn
}

output "validate_audio_function_arn" {
  description = "ARN of the validate audio Lambda function"
  value       = aws_lambda_function.validate_audio.arn
}

output "connect_function_arn" {
  description = "ARN of the connect Lambda function"
  value       = aws_lambda_function.connect.arn
}

output "disconnect_function_arn" {
  description = "ARN of the disconnect Lambda function"
  value       = aws_lambda_function.disconnect.arn
}

output "message_function_arn" {
  description = "ARN of the message Lambda function"
  value       = aws_lambda_function.message.arn
}

output "process_audio_function_name" {
  description = "Name of the process audio Lambda function"
  value       = aws_lambda_function.process_audio.function_name
}

output "validate_audio_function_name" {
  description = "Name of the validate audio Lambda function"
  value       = aws_lambda_function.validate_audio.function_name
}

output "lambda_functions" {
  description = "Map of Lambda function ARNs"
  value = {
    process_audio  = aws_lambda_function.process_audio.arn
    validate_audio = aws_lambda_function.validate_audio.arn
    connect        = aws_lambda_function.connect.arn
    disconnect     = aws_lambda_function.disconnect.arn
    message        = aws_lambda_function.message.arn
  }
}

output "lambda_function_names" {
  description = "Map of Lambda function names"
  value = {
    process_audio  = aws_lambda_function.process_audio.function_name
    validate_audio = aws_lambda_function.validate_audio.function_name
    connect        = aws_lambda_function.connect.function_name
    disconnect     = aws_lambda_function.disconnect.function_name
    message        = aws_lambda_function.message.function_name
  }
} 