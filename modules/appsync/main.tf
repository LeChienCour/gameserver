resource "random_string" "bucket_suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "aws_s3_bucket" "audio_bucket" {
  bucket = "gameserver-voice-chat-audio-${random_string.bucket_suffix.result}"
}

resource "aws_s3_bucket_acl" "audio_bucket_acl" {
  bucket = aws_s3_bucket.audio_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "audio_bucket_versioning" {
  bucket = aws_s3_bucket.audio_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_appsync_graphql_api" "voice_chat_api" {
  name            = var.api_name
  authentication_type = "AMAZON_COGNITO_USER_POOLS"

  user_pool_config {
    user_pool_id      = var.user_pool_id
    aws_region        = var.region
    default_action    = "ALLOW"
  }

  schema = <<EOF
    type Audio {
      format: String!
      encoding: String!
      data: String!
      author: String!
      timestamp: String!
    }

    type Query {
      getAudio(channel: String!): [Audio]
    }

    type Mutation {
      sendAudio(channel: String!, format: String!, encoding: String!, data: String!, author: String!): Audio
    }

    type Subscription {
      onNewAudio(channel: String!): Audio
        @aws_subscribe(mutations: ["sendAudio"])
    }
  EOF
}

resource "aws_appsync_datasource" "s3_datasource" {
  api_id = aws_appsync_graphql_api.voice_chat_api.id
  name   = "s3Datasource"
  type   = "HTTP"

  http_config {
    endpoint = aws_s3_bucket.audio_bucket.bucket_domain_name
  }
}

resource "aws_appsync_resolver" "get_audio_resolver" {
  api_id           = aws_appsync_graphql_api.voice_chat_api.id
  field            = "getAudio"
  type             = "Query"
  data_source      = aws_appsync_datasource.s3_datasource.name
  request_template = <<EOF
    {
      "version": "2018-05-29",
      "operation": "GET",
      "path": "/audios/$util.escapeJavaScript($context.arguments.channel)"
    }
  EOF
  response_template = <<EOF
    #if($context.result.statusCode == 200)
      $context.result.body
    #else
      $util.appendError("Error getting audios", "$context.result.statusCode")
    #end
  EOF
}

resource "aws_appsync_resolver" "send_audio_resolver" {
  api_id           = aws_appsync_graphql_api.voice_chat_api.id
  field            = "sendAudio"
  type             = "Mutation"
  data_source      = aws_appsync_datasource.s3_datasource.name
  request_template = <<EOF
    {
      "version": "2018-05-29",
      "operation": "PUT",
      "path": "/audios/$util.escapeJavaScript($context.arguments.channel)/$util.escapeJavaScript($context.arguments.timestamp).audio",
      "params": {
        "headers": {
          "Content-Type": "$util.escapeJavaScript($context.arguments.format)"
        }
      },
      "body": "$util.escapeJavaScript($context.arguments.data)"
    }
  EOF
  response_template = <<EOF
    #if($context.result.statusCode == 200)
      {
        "format": "$util.escapeJavaScript($context.arguments.format)",
        "encoding": "$util.escapeJavaScript($context.arguments.encoding)",
        "data": "$util.escapeJavaScript($context.arguments.data)",
        "author": "$util.escapeJavaScript($context.arguments.author)",
        "timestamp": "$util.escapeJavaScript($context.arguments.timestamp)"
      }
    #else
      $util.appendError("Error sending audio", "$context.result.statusCode")
    #end
  EOF
}