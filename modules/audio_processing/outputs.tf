output "kms_key_id" {
  description = "ID of the KMS key used for audio encryption"
  value       = aws_kms_key.audio_key.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for audio encryption"
  value       = aws_kms_key.audio_key.arn
}

output "process_audio_lambda_arn" {
  description = "ARN of the audio processing Lambda function"
  value       = aws_lambda_function.process_audio.arn
}

output "validate_audio_lambda_arn" {
  description = "ARN of the audio validation Lambda function"
  value       = aws_lambda_function.validate_audio.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_role.arn
}

output "audio_processing_rule_arn" {
  description = "ARN of the EventBridge rule for audio processing"
  value       = aws_cloudwatch_event_rule.audio_processing_rule.arn
}

output "audio_validation_rule_arn" {
  description = "ARN of the EventBridge rule for audio validation"
  value       = aws_cloudwatch_event_rule.audio_validation_rule.arn
} 