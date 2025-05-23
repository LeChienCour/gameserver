output "key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.audio_key.arn
}

output "key_id" {
  description = "ID of the KMS key"
  value       = aws_kms_key.audio_key.key_id
}

output "alias_arn" {
  description = "ARN of the KMS key alias"
  value       = aws_kms_alias.audio_key_alias.arn
} 