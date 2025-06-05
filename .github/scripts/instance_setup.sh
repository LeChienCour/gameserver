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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Java is installed
if ! command_exists java; then
    echo "Installing Java 21..."
    # Add Amazon Corretto repository
    sudo yum update -y
    sudo yum install -y wget
    wget https://corretto.aws/downloads/latest/amazon-corretto-21-x64-linux-jdk.rpm
    sudo yum localinstall -y amazon-corretto-21-x64-linux-jdk.rpm
    rm amazon-corretto-21-x64-linux-jdk.rpm
    
    # Verify Java installation
    java -version
else
    echo "Java is already installed"
    java -version
fi

# Check if Git is installed
if ! command_exists git; then
    echo "Installing Git..."
    sudo yum install -y git
else
    echo "Git is already installed"
fi

# Create necessary directories
echo "Creating Minecraft directories..."
sudo mkdir -p /home/ec2-user/minecraft/{mods,config,runs,logs}
sudo chown -R ec2-user:ec2-user /home/ec2-user/minecraft

# Create CloudWatch log groups
echo "Creating CloudWatch log groups..."
aws logs create-log-group --log-group-name /minecraft/server-logs || true
aws logs create-log-group --log-group-name /minecraft/voice-chat-logs || true

# Update CloudWatch agent configuration
echo "Updating CloudWatch agent configuration..."
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null << 'EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/home/ec2-user/minecraft/logs/latest.log",
                        "log_group_name": "/minecraft/server-logs",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/home/ec2-user/minecraft/logs/voicechat.log",
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

# Check if Minecraft server exists
if [ ! -f "/home/ec2-user/minecraft/server.jar" ]; then
    echo "Downloading Minecraft server..."
    wget https://piston-data.mojang.com/v1/objects/8dd1a28015f51b1803213892b50b7b4fc76e594d/server.jar -O /home/ec2-user/minecraft/server.jar
fi

# Create systemd service file
echo "Creating Minecraft service..."
sudo tee /etc/systemd/system/minecraft.service > /dev/null << 'EOF'
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/minecraft
ExecStart=/usr/bin/java -Xmx2G -Xms2G -jar server.jar nogui
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
echo "Enabling Minecraft service..."
sudo systemctl daemon-reload
sudo systemctl enable minecraft

# Clean up SSH key
rm -f ~/.ssh/game_server_key

echo "Instance setup completed successfully!" 