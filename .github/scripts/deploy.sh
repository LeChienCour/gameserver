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
INSTANCE_IP="${INSTANCE_IP:-54.163.77.186}"

# Function to safely get SSM parameter with fallback
get_ssm_param() {
    local param_name="$1"
    local default_value="$2"
    local value

    if value=$(aws ssm get-parameter --name "$param_name" --with-decryption --query "Parameter.Value" --output text 2>/dev/null); then
        echo "$value"
    else
        echo "$default_value"
    fi
}

# Determine the stage
if [ -n "$PR_NUMBER" ]; then
    STAGE="pr-${PR_NUMBER}"
elif [ -n "$STAGE" ]; then
    # Validate stage name
    case "$STAGE" in
        "dev"|"qa"|"prod")
            echo "Using provided stage: $STAGE"
            ;;
        *)
            echo "::error::Invalid stage name: $STAGE. Must be one of: dev, qa, prod"
            exit 1
            ;;
    esac
else
    echo "No stage specified, defaulting to dev"
    STAGE="dev"
fi

echo "Using stage: $STAGE"

# Set appropriate default values based on stage
case "$STAGE" in
    "prod")
        DEFAULT_WS_URL="wss://api.gameserver.example.com"
        ;;
    "qa")
        DEFAULT_WS_URL="wss://qa-api.gameserver.example.com"
        ;;
    "pr-"*)
        DEFAULT_WS_URL="wss://${STAGE}-api.gameserver.example.com"
        ;;
    *)  # dev and any other case
        DEFAULT_WS_URL="wss://dev-api.gameserver.example.com"
        ;;
esac

# Try to get values from SSM, fall back to stage-appropriate defaults
echo "Fetching configuration values for stage: $STAGE"
WEBSOCKET_STAGE_URL=$(get_ssm_param "/gameserver/$STAGE/websocket/stage_url" "$DEFAULT_WS_URL")
WEBSOCKET_API_KEY=$(get_ssm_param "/gameserver/$STAGE/websocket/api_key" "default-api-key-for-$STAGE")
USER_POOL_ID=$(get_ssm_param "/gameserver/$STAGE/cognito/user_pool_id" "us-east-1_dummy_$STAGE")
USER_POOL_CLIENT_ID=$(get_ssm_param "/gameserver/$STAGE/cognito/user_pool_client_id" "client-id-$STAGE")

# Create mods directory and set permissions
echo "Setting up mods directory..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo mkdir -p /opt/minecraft/server/mods && sudo chown -R ec2-user:ec2-user /opt/minecraft/server/mods"

# Create config directory for voice chat
echo "Setting up voice chat configuration..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo mkdir -p /opt/minecraft/server/runs/client/config && sudo chown -R ec2-user:ec2-user /opt/minecraft/server/runs/client/config"

# Create CloudWatch log groups if they don't exist
echo "Creating CloudWatch log groups for stage: $STAGE..."
LOG_GROUPS=(
    "/game-server/${STAGE}/cloud-init"
    "/game-server/${STAGE}/system"
    "/game-server/${STAGE}/minecraft"
    "/game-server/${STAGE}/voicechat"
)

for LOG_GROUP in "${LOG_GROUPS[@]}"; do
    aws logs create-log-group --log-group-name "$LOG_GROUP" --tags "Environment=${STAGE}" 2>/dev/null || true
    aws logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days 7
done

# Update CloudWatch agent configuration to include voice chat logs
echo "Updating CloudWatch configuration..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "cat > /tmp/amazon-cloudwatch-agent.json << 'EOF'
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
            \"log_group_name\": \"/game-server/${STAGE}/cloud-init\",
            \"log_stream_name\": \"{instance_id}\",
            \"retention_in_days\": 7
          },
          {
            \"file_path\": \"/var/log/messages\",
            \"log_group_name\": \"/game-server/${STAGE}/system\",
            \"log_stream_name\": \"{instance_id}\",
            \"retention_in_days\": 7
          },
          {
            \"file_path\": \"/opt/minecraft/server/logs/latest.log\",
            \"log_group_name\": \"/game-server/${STAGE}/minecraft\",
            \"log_stream_name\": \"{instance_id}\",
            \"retention_in_days\": 7
          },
          {
            \"file_path\": \"/opt/minecraft/server/logs/voicechat/latest.log\",
            \"log_group_name\": \"/game-server/${STAGE}/voicechat\",
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
EOF
sudo mv /tmp/amazon-cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sudo chown root:root /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sudo chmod 644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"

# Create voice chat configuration file
echo "Creating voice chat configuration..."
CONFIG_CONTENT="enableVoiceChat = true

#Default voice chat volume (0.0 to 1.0). This might be overridden by client-side settings later.
defaultVolume = 0.7

#Maximum distance (in blocks) at which players can hear each other.
maxVoiceDistance = 64

#Number of times to attempt reconnection to the voice gateway if connection is lost.
reconnectionAttempts = 3

#Delay in seconds between reconnection attempts.
reconnectionDelay = 5

#WebSocket Gateway URL for voice chat communication
websocketStageUrl = \"$WEBSOCKET_STAGE_URL\"

#API Key for WebSocket Gateway authentication
websocketApiKey = \"$WEBSOCKET_API_KEY\"

#Cognito User Pool ID for authentication
userPoolId = \"$USER_POOL_ID\"

#Cognito User Pool Client ID for authentication
userPoolClientId = \"$USER_POOL_CLIENT_ID\"

#The name of the selected microphone device. Leave empty to use system default.
selectedMicrophone = \"\"

#Whether to use the system default microphone instead of a specific device.
useSystemDefaultMic = true

#Microphone boost/gain level (1.0 is normal, increase for quiet mics).
microphoneBoost = 1.0

#Enable debug logging for voice chat"

if [ "$STAGE" = "prod" ]; then
    CONFIG_CONTENT="$CONFIG_CONTENT
enableDebugLogging = false"
else
    CONFIG_CONTENT="$CONFIG_CONTENT
enableDebugLogging = true"
fi

ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "echo '$CONFIG_CONTENT' > /opt/minecraft/server/runs/client/config/voicechatmod-common.toml"

# Create voice chat log directory
echo "Setting up voice chat log directory..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo mkdir -p /opt/minecraft/server/logs/voicechat && sudo chown -R ec2-user:ec2-user /opt/minecraft/server/logs/voicechat"

# Copy mod file to instance using SCP
echo "Copying mod files..."
scp -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no \
  ./mod_source/build/libs/*.jar ec2-user@$INSTANCE_IP:/opt/minecraft/server/mods/

# Check and install Java if needed
echo "Checking Java installation..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "if ! command -v java &> /dev/null || ! java -version 2>&1 | grep -q 'version \"21'; then
    echo 'Installing Java 21...'
    sudo yum remove -y java-* || true
    sudo yum install -y java-21-amazon-corretto
fi"

# Verify Java version
echo "Verifying Java version..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "java -version"

# Download Minecraft server if not exists
echo "Checking/Downloading Minecraft server..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "cd /opt/minecraft/server && \
if [ ! -f server.jar ]; then
    echo 'Downloading Minecraft server...'
    sudo curl -o server.jar 'https://piston-data.mojang.com/v1/objects/8dd1a28015f51b1803213892b50b7b4fc76e594d/server.jar'
    sudo chown ec2-user:ec2-user server.jar
    echo 'eula=true' > eula.txt
fi"

# Verify server.jar exists
echo "Checking for server.jar..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "if [ ! -f /opt/minecraft/server/server.jar ]; then
    echo 'Error: server.jar not found in /opt/minecraft/server/'
    exit 1
fi"

# Create systemd service file for Minecraft
echo "Creating Minecraft systemd service..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo tee /etc/systemd/system/minecraft.service << 'EOF'
[Unit]
Description=Minecraft Server
After=network.target

[Service]
WorkingDirectory=/opt/minecraft/server
User=ec2-user
Group=ec2-user
Restart=always
RestartSec=10

ExecStart=/usr/bin/java -Xmx2G -Xms1G -jar server.jar nogui
ExecStop=/usr/bin/screen -p 0 -S minecraft -X eval 'stuff \"say SERVER SHUTTING DOWN IN 10 SECONDS. SAVING ALL WORLDS.\"\015'
ExecStop=/bin/sleep 10
ExecStop=/usr/bin/screen -p 0 -S minecraft -X eval 'stuff \"save-all\"\015'
ExecStop=/usr/bin/screen -p 0 -S minecraft -X eval 'stuff \"stop\"\015'

[Install]
WantedBy=multi-user.target
EOF"

# Reload systemd and enable service
echo "Configuring Minecraft service..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo systemctl daemon-reload && sudo systemctl enable minecraft.service"

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