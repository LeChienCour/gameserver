#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Not running as root. Re-executing with sudo..."
  exec sudo -E bash "$0" "$@"
fi

echo "Starting instance setup..."

# Update package lists and install required packages
echo "Updating system and installing required packages..."
sudo yum update -y
sudo yum install -y wget gnupg jq amazon-cloudwatch-agent

# Install Amazon Corretto 21
echo "Installing Amazon Corretto 21..."
sudo rpm --import https://yum.corretto.aws/corretto.key
sudo curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
sudo yum install -y java-21-amazon-corretto-devel

# Create Minecraft directory structure
echo "Creating Minecraft directory structure..."
sudo mkdir -p /opt/minecraft/{server,mods,config,logs,runs/client/config}

# Set permissions
echo "Setting permissions..."
sudo chown -R ec2-user:ec2-user /opt/minecraft
sudo chmod -R 755 /opt/minecraft

# Install NeoForge
echo "Installing NeoForge..."
cd /opt/minecraft/server

# Download NeoForge installer
echo "Downloading NeoForge installer..."
sudo -u ec2-user wget https://maven.neoforged.net/releases/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-installer.jar

# Run installer
echo "Running NeoForge installer..."
sudo -u ec2-user java -jar neoforge-21.4.136-installer.jar --installServer

# Create a symlink to the server JAR
echo "Creating symlink to server JAR..."
ln -sf "/opt/minecraft/server/libraries/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-server.jar" "/opt/minecraft/server/neoforge-21.4.136.jar"

# Clean up installer
sudo -u ec2-user rm -f neoforge-21.4.136-installer.jar

# Accept EULA and create basic server configuration
echo "Configuring server..."
sudo -u ec2-user bash -c 'echo "eula=true" > eula.txt'
sudo -u ec2-user bash -c 'cat > server.properties << EOF
server-port=25565
max-players=20
difficulty=normal
gamemode=survival
EOF'

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
Description=Minecraft NeoForge Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/minecraft/server
Environment="JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto"
Environment="PATH=/usr/lib/jvm/java-21-amazon-corretto/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=/usr/lib/jvm/java-21-amazon-corretto/bin/java -Xmx2G -Xms2G -jar neoforge-21.4.136.jar nogui
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Minecraft service
echo "Enabling and starting Minecraft service..."
sudo systemctl enable minecraft
sudo systemctl start minecraft

echo "Instance setup completed successfully!" 