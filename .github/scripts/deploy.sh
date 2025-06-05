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
if [ -z "$INSTANCE_IP" ]; then
    echo "::error::INSTANCE_IP environment variable is required but not set. This should be provided from Terraform outputs."
    exit 1
fi

echo "Using instance IP: $INSTANCE_IP"

# Function to safely get SSM parameter with fallback
get_ssm_param() {
    local param_name=$1
    local fallback_value=$2
    local value

    # Try to get from SSM
    if value=$(aws ssm get-parameter --name "$param_name" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null); then
        echo "$value"
    else
        echo "$fallback_value"
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

# Get configuration values from SSM or use defaults
WEBSOCKET_URL=$(get_ssm_param "/gameserver/$STAGE/websocket/stage_url" "$DEFAULT_WS_URL")
API_KEY=$(get_ssm_param "/gameserver/$STAGE/websocket/api_key" "dev-key")
USER_POOL_ID=$(get_ssm_param "/gameserver/$STAGE/cognito/user_pool_id" "us-east-1_dev")
USER_POOL_CLIENT_ID=$(get_ssm_param "/gameserver/$STAGE/cognito/user_pool_client_id" "dev-client")

# Create voice chat configuration
echo "Creating voice chat configuration..."
cat > voicechatmod.toml << EOF
# Voice Chat Mod Configuration
enableVoiceChat = true
defaultVolume = 1.0
websocketStageUrl = "$WEBSOCKET_URL"
apiKey = "$API_KEY"
userPoolId = "$USER_POOL_ID"
userPoolClientId = "$USER_POOL_CLIENT_ID"
EOF

# Copy mod files to instance
echo "Copying mod files to instance..."
scp -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no voicechatmod.toml ec2-user@$INSTANCE_IP:/home/ec2-user/minecraft/config/
scp -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no mod_source/build/libs/*.jar ec2-user@$INSTANCE_IP:/home/ec2-user/minecraft/mods/

# Set permissions
echo "Setting permissions..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "chmod 644 /home/ec2-user/minecraft/config/voicechatmod.toml /home/ec2-user/minecraft/mods/*.jar"

# Restart Minecraft server and CloudWatch agent
echo "Restarting services..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo systemctl restart minecraft && sudo systemctl restart amazon-cloudwatch-agent"

# Wait for server to start and mod to load
echo "Waiting for server to start..."
MAX_ATTEMPTS=60
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo journalctl -u minecraft -n 50 | grep -q 'VoiceChatMod loaded successfully'"; then
        echo "✅ Server started and mod loaded successfully"
        echo "::set-output name=status::success"
        echo "::set-output name=message::Server running successfully with mod deployed"
        exit 0
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 5
done

echo "❌ Server failed to start or mod failed to load"
exit 1

# Clean up SSH key
rm -f ~/.ssh/game_server_key 