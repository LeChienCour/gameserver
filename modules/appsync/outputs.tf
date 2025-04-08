output "appsync_api_id" {
  description = "The ID of the AppSync API"
  value       = aws_appsync_graphql_api.voice_chat_api.id
}

output "audio_bucket_domain_name" {
  description = "The domain name of the S3 bucket for audio storage"
  value       = aws_s3_bucket.audio_bucket.bucket_domain_name
}