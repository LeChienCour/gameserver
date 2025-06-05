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

# Function to get Java version
get_java_version() {
    java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1
}

# Function to check if Java is Amazon Corretto
is_corretto() {
    java -version 2>&1 | grep -q "Corretto"
}

# Check and update Java if needed
if command_exists java; then
    CURRENT_JAVA_VERSION=$(get_java_version)
    echo "Current Java version: $CURRENT_JAVA_VERSION"
    
    if [ "$CURRENT_JAVA_VERSION" != "21" ] || ! is_corretto; then
        echo "Updating Java to Amazon Corretto 21 (headless)..."
        # Remove existing Java installation
        sudo apt remove -y openjdk-*
        # Add Amazon Corretto repository
        wget -O- https://apt.corretto.aws/corretto.key | sudo apt-key add -
        sudo add-apt-repository 'deb https://apt.corretto.aws stable main'
        sudo apt update
        # Install headless variant
        sudo apt install -y java-21-amazon-corretto-headless
        
        # Verify new Java installation
        NEW_JAVA_VERSION=$(get_java_version)
        echo "New Java version: $NEW_JAVA_VERSION"
        
        if [ "$NEW_JAVA_VERSION" != "21" ] || ! is_corretto; then
            echo "::error::Failed to install Amazon Corretto 21. Current version: $NEW_JAVA_VERSION"
            exit 1
        fi
    else
        echo "Amazon Corretto 21 is already installed"
    fi
else
    echo "Installing Amazon Corretto 21 (headless)..."
    # Add Amazon Corretto repository
    wget -O- https://apt.corretto.aws/corretto.key | sudo apt-key add -
    sudo add-apt-repository 'deb https://apt.corretto.aws stable main'
    sudo apt update
    # Install headless variant
    sudo apt install -y java-21-amazon-corretto-headless
fi

# Check if Git is installed
if ! command_exists git; then
    echo "Installing Git..."
    sudo apt install -y git
else
    echo "Git is already installed"
fi

# Get current user
CURRENT_USER=$(whoami)
MINECRAFT_DIR="/home/$CURRENT_USER/minecraft"

# Create necessary directories
echo "Creating Minecraft directories..."
sudo mkdir -p "$MINECRAFT_DIR"/{mods,config,runs,logs}
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$MINECRAFT_DIR"

# Install and configure CloudWatch agent
echo "Installing CloudWatch agent..."
sudo apt install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration directory if it doesn't exist
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/

# Create CloudWatch log groups
echo "Creating CloudWatch log groups..."
aws logs create-log-group --log-group-name /minecraft/server-logs || true
aws logs create-log-group --log-group-name /minecraft/voice-chat-logs || true

# Update CloudWatch agent configuration
echo "Updating CloudWatch agent configuration..."
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "$MINECRAFT_DIR/logs/latest.log",
                        "log_group_name": "/minecraft/server-logs",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "$MINECRAFT_DIR/logs/voicechat.log",
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

# Start and enable CloudWatch agent
echo "Starting CloudWatch agent..."
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl start amazon-cloudwatch-agent

# Check if Minecraft server exists
if [ ! -f "$MINECRAFT_DIR/server.jar" ]; then
    echo "Downloading Minecraft server..."
    wget https://piston-data.mojang.com/v1/objects/8dd1a28015f51b1803213892b50b7b4fc76e594d/server.jar -O "$MINECRAFT_DIR/server.jar"
fi

# Create systemd service file
echo "Creating Minecraft service..."
sudo tee /etc/systemd/system/minecraft.service > /dev/null << EOF
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
WorkingDirectory=$MINECRAFT_DIR
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