#!/bin/bash
set -e

echo "Starting deployment..."

# Set up SSH key for deployment with proper RSA format
mkdir -p ~/.ssh
echo "-----BEGIN RSA PRIVATE KEY-----" > ~/.ssh/game_server_key
echo "$SSH_PRIVATE_KEY" | fold -w 64 >> ~/.ssh/game_server_key
echo "-----END RSA PRIVATE KEY-----" >> ~/.ssh/game_server_key
chmod 600 ~/.ssh/game_server_key

# Get instance public IP
INSTANCE_IP="54.163.77.186"

# Get WebSocket and Cognito configuration from SSM Parameter Store
echo "Fetching configuration values..."
WEBSOCKET_STAGE_URL=$(aws ssm get-parameter --name "/gameserver/dev/websocket/stage_url" --with-decryption --query "Parameter.Value" --output text)
WEBSOCKET_API_KEY=$(aws ssm get-parameter --name "/gameserver/dev/websocket/api_key" --with-decryption --query "Parameter.Value" --output text)
USER_POOL_ID=$(aws ssm get-parameter --name "/gameserver/dev/cognito/user_pool_id" --with-decryption --query "Parameter.Value" --output text)
USER_POOL_CLIENT_ID=$(aws ssm get-parameter --name "/gameserver/dev/cognito/user_pool_client_id" --with-decryption --query "Parameter.Value" --output text)

# Create mods directory and set permissions
echo "Setting up mods directory..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo mkdir -p /opt/minecraft/server/mods && sudo chown -R ec2-user:ec2-user /opt/minecraft/server/mods"

# Create config directory for voice chat
echo "Setting up voice chat configuration..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo mkdir -p /opt/minecraft/server/runs/client/config && sudo chown -R ec2-user:ec2-user /opt/minecraft/server/runs/client/config"

# Update CloudWatch agent configuration to include voice chat logs
echo "Updating CloudWatch configuration..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  \"agent\": {
    \"metrics_collection_interval\": 60,
    \"run_as_user\": \"root\"
  },
  \"logs\": {
    \"logs_collected\": {
      \"files\": {
        \"collect_list\": [
          {
            \"file_path\": \"/var/log/cloud-init-output.log\",
            \"log_group_name\": \"/game-server/dev/cloud-init\",
            \"log_stream_name\": \"{instance_id}\",
            \"retention_in_days\": 7
          },
          {
            \"file_path\": \"/var/log/messages\",
            \"log_group_name\": \"/game-server/dev/system\",
            \"log_stream_name\": \"{instance_id}\",
            \"retention_in_days\": 7
          },
          {
            \"file_path\": \"/opt/minecraft/server/logs/latest.log\",
            \"log_group_name\": \"/game-server/dev/minecraft\",
            \"log_stream_name\": \"{instance_id}\",
            \"retention_in_days\": 7
          },
          {
            \"file_path\": \"/opt/minecraft/server/logs/voicechat/latest.log\",
            \"log_group_name\": \"/game-server/dev/voicechat\",
            \"log_stream_name\": \"{instance_id}\",
            \"retention_in_days\": 7
          }
        ]
      }
    }
  },
  \"metrics\": {
    \"metrics_collected\": {
      \"mem\": {
        \"measurement\": [\"mem_used_percent\"]
      },
      \"swap\": {
        \"measurement\": [\"swap_used_percent\"]
      },
      \"disk\": {
        \"measurement\": [\"used_percent\"],
        \"resources\": [\"/\"]
      }
    },
    \"append_dimensions\": {
      \"InstanceId\": \"\${aws:InstanceId}\"
    }
  }
}
EOF"

# Create voice chat configuration file
echo "Creating voice chat configuration..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "cat > /opt/minecraft/server/runs/client/config/voicechatmod-common.toml << EOF
#Enable or disable the voice chat functionality globally.
enableVoiceChat = true

#Default voice chat volume (0.0 to 1.0). This might be overridden by client-side settings later.
# Default: 0.7
# Range: 0.0 ~ 1.0
defaultVolume = 0.7

#Maximum distance (in blocks) at which players can hear each other. Set to 0 for global chat (if server supports).
# Default: 64
# Range: 0 ~ 256
maxVoiceDistance = 64

#Number of times to attempt reconnection to the voice gateway if connection is lost.
# Default: 3
# Range: 0 ~ 10
reconnectionAttempts = 3

#Delay in seconds between reconnection attempts.
# Default: 5
# Range: 1 ~ 30
reconnectionDelay = 5

#WebSocket Gateway URL for voice chat communication
websocketStageUrl = \"${WEBSOCKET_STAGE_URL}\"

#API Key for WebSocket Gateway authentication
websocketApiKey = \"${WEBSOCKET_API_KEY}\"

#Cognito User Pool ID for authentication
userPoolId = \"${USER_POOL_ID}\"

#Cognito User Pool Client ID for authentication
userPoolClientId = \"${USER_POOL_CLIENT_ID}\"

#The name of the selected microphone device. Leave empty to use system default.
selectedMicrophone = \"\"

#Whether to use the system default microphone instead of a specific device.
useSystemDefaultMic = true

#Microphone boost/gain level (1.0 is normal, increase for quiet mics).
# Default: 1.0
# Range: 0.1 ~ 5.0
microphoneBoost = 1.0

#Enable debug logging for voice chat
enableDebugLogging = true
EOF"

# Create voice chat log directory
echo "Setting up voice chat log directory..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo mkdir -p /opt/minecraft/server/logs/voicechat && sudo chown -R ec2-user:ec2-user /opt/minecraft/server/logs/voicechat"

# Copy mod file to instance using SCP
echo "Copying mod files..."
scp -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no \
  ./mod_source/build/libs/*.jar ec2-user@$INSTANCE_IP:/opt/minecraft/server/mods/

# Set permissions and restart server
echo "Setting permissions and restarting server..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo chmod -R 755 /opt/minecraft/server/mods /opt/minecraft/server/runs/client/config /opt/minecraft/server/logs/voicechat && sudo systemctl restart minecraft && sudo systemctl restart amazon-cloudwatch-agent"

# Wait for server to start and verify mod
echo "Waiting for server to start..."
for i in {1..60}; do
  if ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo test -f /opt/minecraft/server/logs/latest.log && sudo grep -q 'Done.*For help' /opt/minecraft/server/logs/latest.log && sudo grep -q 'VoiceChatMod' /opt/minecraft/server/logs/latest.log"; then
    echo "Server started and mod loaded successfully"
    echo "::set-output name=status::success"
    echo "::set-output name=message::Server running successfully with mod deployed"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "::error::Timeout waiting for server to start or mod to load"
    exit 1
  fi
  echo "Still waiting... (attempt $i/60)"
  sleep 5
done

# Clean up SSH key
rm -f ~/.ssh/game_server_key 