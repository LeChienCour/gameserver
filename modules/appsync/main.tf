resource "random_string" "bucket_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_s3_bucket" "audio_bucket" {
  bucket             = "gameserver-voice-chat-audio-${random_string.bucket_suffix.result}"
  object_lock_enabled = true
}

resource "aws_s3_bucket_object_lock_configuration" "audio_bucket_lock" {
  bucket = aws_s3_bucket.audio_bucket.id

  rule {
    default_retention {
      mode  = "GOVERNANCE"
      days  = 30
    }
  }
}

resource "aws_s3_bucket_versioning" "audio_bucket_versioning" {
  bucket = aws_s3_bucket.audio_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "appsync_service_role" {
  name = "appsync-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "appsync.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "appsync_service_policy" {
  name = "appsync-service-policy"
  role = aws_iam_role.appsync_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.audio_bucket.arn,
          "${aws_s3_bucket.audio_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_appsync_graphql_api" "voice_chat_api" {
  name                = var.api_name
  authentication_type = "API_KEY"
  
  schema = <<EOF
schema {
  query: Query
  mutation: Mutation
  subscription: Subscription
}

type Audio {
  format: String!
  encoding: String!
  data: String!
  author: String!
  timestamp: String!
  method: String!
}

type Query {
  getAudio(channel: String!): [Audio]
}

type Mutation {
  sendAudio(
    channel: String!
    format: String!
    encoding: String!
    data: String!
    author: String!
    timestamp: String!
    method: String!
  ): Audio
}

type Subscription {
  onReceiveAudio(channel: String!): Audio
    @aws_subscribe(mutations: ["sendAudio"])
}
EOF

  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_service_role.arn
    field_log_level          = "ALL"
  }
}

resource "aws_appsync_api_key" "voice_chat_api_key" {
  api_id      = aws_appsync_graphql_api.voice_chat_api.id
  description = "API Key for Voice Chat API for Testing"
  expires     = timeadd(timestamp(), "8760h")  # 1 year from creation
}

resource "aws_appsync_api_key" "voice_chat_api_default_key" {
  api_id      = aws_appsync_graphql_api.voice_chat_api.id
  description = "Default API Key for Voice Chat API"
  expires     = timeadd(timestamp(), "8760h")  # 1 year from creation
}

resource "aws_appsync_datasource" "s3_datasource" {
  api_id           = aws_appsync_graphql_api.voice_chat_api.id
  name             = "s3Datasource"
  service_role_arn = aws_iam_role.appsync_service_role.arn
  type             = "HTTP"

  http_config {
    endpoint = "https://${aws_s3_bucket.audio_bucket.bucket_regional_domain_name}"
  }
}

resource "aws_appsync_resolver" "get_audio_resolver" {
  api_id      = aws_appsync_graphql_api.voice_chat_api.id
  type        = "Query"
  field       = "getAudio"
  data_source = aws_appsync_datasource.s3_datasource.name

  request_template = <<EOF
{
  "version": "2018-05-29",
  "method": "GET",
  "resourcePath": "/audios/$util.urlEncode($context.arguments.channel)",
  "params":{
    "headers": {
      "Content-Type": "application/json"
    }
  }
}
EOF

  response_template = <<EOF
#if($context.result.statusCode == 200)
  $util.toJson($context.result.body)
#else
  $util.error("Failed to fetch audio", "AudioFetchError")
#end
EOF
}

resource "aws_appsync_resolver" "send_audio_resolver" {
  api_id      = aws_appsync_graphql_api.voice_chat_api.id
  type        = "Mutation"
  field       = "sendAudio"
  data_source = aws_appsync_datasource.s3_datasource.name

  request_template = <<EOF
{
  "version": "2018-05-29",
  "method": "PUT",
  "resourcePath": "/audios/$util.urlEncode($context.arguments.channel)/$util.urlEncode($context.arguments.timestamp).audio",
  "params": {
    "headers": {
      "Content-Type": "$util.escapeJavaScript($context.arguments.format)"
    },
    "body": "$util.escapeJavaScript($context.arguments.data)"
  }
}
EOF

  response_template = <<EOF
#if($context.result.statusCode == 200)
  {
    "format": "$context.arguments.format",
    "encoding": "$context.arguments.encoding",
    "data": "$context.arguments.data",
    "author": "$context.arguments.author",
    "timestamp": "$context.arguments.timestamp"
  }
#else
  $util.error("Failed to save audio", "AudioSaveError")
#end
EOF
}

resource "aws_appsync_datasource" "none" {
  api_id = aws_appsync_graphql_api.voice_chat_api.id
  name   = "NONE"
  type   = "NONE"
}

resource "aws_appsync_resolver" "onreceive_audio_resolver" {
  api_id      = aws_appsync_graphql_api.voice_chat_api.id
  type        = "Subscription"
  field       = "onReceiveAudio"
  data_source = aws_appsync_datasource.none.name

  request_template = <<EOF
{
    "version": "2018-05-29",
    "payload": {}
}
EOF

  response_template = <<EOF
$util.toJson($context.result)
EOF
}