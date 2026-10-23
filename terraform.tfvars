# AWS Region
region = "us-east-1"

# VPC Configuration
vpc_cidr            = "10.0.0.0/16"
public_subnets_cidr = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
vpc_name            = "game-server-vpc"

# Security Configuration (ssh_cidr = "" disables port 22 and uses SSM Session Manager)
security_group_name = "game-server-sg"
game_port           = 25565
ssh_cidr            = ""
game_protocol       = "tcp"

# EC2 Configuration (set enable_ec2_server = false for $0/idle Serverless Voice-Only mode)
enable_ec2_server = true
ami_id            = null
instance_type     = "t4g.medium"

# Cognito Configuration
user_pool_name  = "game-users"
app_client_name = "game-client"
admin_role_name = "game-admin-role"

# Common Configuration
environment  = "dev"
project_name = "voice-chat"
prefix       = "voice-chat"

# EventBridge Configuration
event_bus_name     = "voice-chat-event-bus"
event_source       = "game-server"
event_detail_type  = "GameEvent"
log_retention_days = 30

# WebSocket Configuration
websocket_prefix     = "game-server-ws"
websocket_stage_name = "test"

# Storage Configuration
audio_bucket_name    = "voice-chat-audio-bucket"
audio_retention_days = 7
connections_table    = "voice-chat-connections"

# Lambda Configuration
lambda_functions = {
  process_audio  = "lambda/process_audio.zip"
  validate_audio = "lambda/validate_audio.zip"
  connect        = "lambda/connect.zip"
  disconnect     = "lambda/disconnect.zip"
  message        = "lambda/message.zip"
  authorizer     = "lambda/authorizer.zip"
}

# Feature & FinOps Flags
enable_echo_mode         = true
enable_direct_broadcast  = true
enable_audio_archival    = false
max_voice_distance       = 64
enable_custom_authorizer = false
