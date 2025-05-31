# KMS Key for audio encryption
resource "aws_kms_key" "audio_key" {
  description             = "KMS key for audio encryption - ${var.stage} environment"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
    Stage       = var.stage
  }
}

# KMS Alias for the key
resource "aws_kms_alias" "audio_key_alias" {
  name          = "alias/${var.prefix}-audio-key"
  target_key_id = aws_kms_key.audio_key.key_id
} 