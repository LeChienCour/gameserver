vpc_cidr            = "10.0.0.0/16"
public_subnets_cidr = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
vpc_name            = "game-server-vpc"

security_group_name = "game-server-sg"
game_port           = 27015
ssh_cidr            = "0.0.0.0/0"
game_protocol       = "udp"

ami_id        = "ami-0e3faa5e960844571"
instance_type = "t4g.small"

user_pool_name  = "game-users"
app_client_name = "game-client"
admin_role_name = "game-admin-role"

# EventBridge Configuration
eventbridge_prefix            = "voice-chat"
eventbridge_bus_name          = "voice-chat-event-bus"
eventbridge_event_source      = "game-server"
eventbridge_event_detail_type = "SendAudioEvent"
eventbridge_log_retention_days = 30
enable_echo_mode              = "true"

# Lambda functions configuration
lambda_functions = {
  connect    = "lambda/connect.zip"
  disconnect = "lambda/disconnect.zip"
  message    = "lambda/message.zip"
  process_audio  = "lambda/process_audio.zip"
  validate_audio = "lambda/validate_audio.zip"
}