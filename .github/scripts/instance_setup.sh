#!/bin/bash
set -e

echo "Starting instance setup..."

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

# Install Java and create directories
echo "Installing Java and creating directories..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "sudo yum install -y java-21-amazon-corretto-devel && \
    sudo mkdir -p /opt/minecraft/server/mods /opt/minecraft/server/runs/client/config /opt/minecraft/server/logs/voicechat && \
    sudo chown -R ec2-user:ec2-user /opt/minecraft/server"

# Create CloudWatch log groups if they don't exist
echo "Creating CloudWatch log groups..."
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

# Update CloudWatch agent configuration
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

# Download Minecraft server if not exists
echo "Checking/Downloading Minecraft server..."
ssh -i ~/.ssh/game_server_key -o StrictHostKeyChecking=no ec2-user@$INSTANCE_IP "cd /opt/minecraft/server && \
if [ ! -f server.jar ]; then
    echo 'Downloading Minecraft server...'
    sudo curl -o server.jar 'https://piston-data.mojang.com/v1/objects/8dd1a28015f51b1803213892b50b7b4fc76e594d/server.jar'
    sudo chown ec2-user:ec2-user server.jar
    echo 'eula=true' > eula.txt
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

# Clean up SSH key
rm -f ~/.ssh/game_server_key

echo "Instance setup completed successfully!" 