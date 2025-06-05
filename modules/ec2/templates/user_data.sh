#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Not running as root. Re-executing with sudo..."
  exec sudo -E bash "$0" "$@"
fi

echo "Starting instance setup..."

# Update system and install required packages
echo "Updating system and installing required packages..."
sudo yum update -y
sudo yum install -y java-21-amazon-corretto-headless

# Create Minecraft directory structure
echo "Creating Minecraft directory structure..."
sudo mkdir -p /opt/minecraft/{server,mods,config,logs}

# Set permissions
echo "Setting permissions..."
sudo chown -R ec2-user:ec2-user /opt/minecraft
sudo chmod -R 755 /opt/minecraft

# Set up NeoForge installation
echo "Setting up NeoForge installation..."
cd /opt/minecraft/server

# Download NeoForge installer and universal JAR
echo "Downloading NeoForge files..."
sudo -u ec2-user wget -v "https://maven.neoforged.net/releases/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-universal.jar"

# Verify download
if [ ! -f "neoforge-21.4.136-universal.jar" ]; then
    echo "Failed to download NeoForge universal JAR"
    exit 1
fi

# Create symlink to server JAR
echo "Creating symlink to server JAR..."
sudo ln -sf "neoforge-21.4.136-universal.jar" "server.jar"

# Verify symlink was created
if [ ! -L "server.jar" ]; then
    echo "Failed to create symlink to NeoForge server JAR"
    exit 1
fi

echo "✅ NeoForge setup completed"

# Clean up installer
sudo -u ec2-user rm -f neoforge-21.4.136-universal.jar

# Accept EULA and create basic server configuration
echo "Configuring server..."
sudo -u ec2-user bash -c 'echo "eula=true" > eula.txt'
sudo -u ec2-user bash -c 'cat > server.properties << EOF
server-port=25565
max-players=20
difficulty=normal
gamemode=survival
EOF'

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
sudo yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent config directory
echo "Creating CloudWatch agent config directory..."
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

# Create CloudWatch agent config
cat << 'EOF' | sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/minecraft/logs/latest.log",
            "log_group_name": "/minecraft/server-logs",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/minecraft/logs/voice-chat.log",
            "log_group_name": "/minecraft/voice-chat-logs",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
echo "Starting CloudWatch agent..."
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl start amazon-cloudwatch-agent

# Create Minecraft server service
echo "Creating Minecraft server service..."
cat << 'EOF' | sudo tee /etc/systemd/system/minecraft.service > /dev/null
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/minecraft/server
ExecStart=/usr/bin/java -Xmx2G -Xms2G -jar server.jar nogui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo "Enabling and starting Minecraft service..."
sudo systemctl daemon-reload
sudo systemctl enable minecraft
sudo systemctl start minecraft

echo "Instance setup completed successfully!" 