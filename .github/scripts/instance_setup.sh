#!/bin/bash
set -e

echo "Starting instance setup..."

# Get instance public IP and AWS region
if [ -z "$INSTANCE_IP" ]; then
    echo "::error::INSTANCE_IP environment variable is required but not set. This should be provided from Terraform outputs."
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo "::error::AWS_REGION environment variable is required but not set."
    exit 1
fi

echo "Using instance IP: $INSTANCE_IP"
echo "Using AWS Region: $AWS_REGION"

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

# Update package lists and install required packages
echo "Updating system and installing required packages..."
sudo yum update -y
sudo yum install -y wget gnupg jq amazon-cloudwatch-agent

# Check and update Java if needed
if command_exists java; then
    CURRENT_JAVA_VERSION=$(get_java_version)
    echo "Current Java version: $CURRENT_JAVA_VERSION"
fi

if ! command_exists java || [ "$CURRENT_JAVA_VERSION" != "21" ] || ! is_corretto; then
    # Remove existing Java installation if present
    if command_exists java; then
        sudo yum remove -y java-*
        echo "Existing Java installation removed"
    fi

    echo "Installing Amazon Corretto 21..."
    # Install Amazon Corretto 21
    sudo rpm --import https://yum.corretto.aws/corretto.key
    sudo curl -L -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
    sudo yum install -y java-21-amazon-corretto-devel
    
    # Verify installation
    NEW_JAVA_VERSION=$(get_java_version)
    if [ "$NEW_JAVA_VERSION" != "21" ] || ! is_corretto; then
        echo "::error::Failed to install Amazon Corretto 21. Current version: $NEW_JAVA_VERSION"
        exit 1
    fi
    echo "✅ Amazon Corretto 21 installed successfully"
else
    echo "✅ Amazon Corretto 21 is already installed"
fi

# Check if Git is installed
if ! command_exists git; then
    echo "Installing Git..."
    sudo yum install -y git
else
    echo "Git is already installed"
fi

# Get current user and create Minecraft directory
CURRENT_USER=$(whoami)
MINECRAFT_DIR="/opt/minecraft"

echo "Creating Minecraft directory structure..."
# Create base directory first
sudo mkdir -p "$MINECRAFT_DIR"
sudo chown "$CURRENT_USER:$CURRENT_USER" "$MINECRAFT_DIR"
sudo chmod 755 "$MINECRAFT_DIR"

# Create subdirectories
sudo -u "$CURRENT_USER" mkdir -p "$MINECRAFT_DIR"/{server,backups,logs,mods,config}
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$MINECRAFT_DIR"

# Install NeoForge
echo "Installing NeoForge..."
cd "$MINECRAFT_DIR/server"
sudo -u "$CURRENT_USER" wget -q https://maven.neoforged.net/releases/net/neoforged/neoforge/1.21.1/neoforge-1.21.1-installer.jar
sudo -u "$CURRENT_USER" java -jar neoforge-1.21.1-installer.jar --installServer
sudo -u "$CURRENT_USER" rm -f neoforge-1.21.1-installer.jar

# Accept EULA and create basic server configuration
echo "Configuring server..."
sudo -u "$CURRENT_USER" bash -c 'echo "eula=true" > eula.txt'
sudo -u "$CURRENT_USER" bash -c 'cat > server.properties << EOF
server-port=25565
max-players=20
difficulty=normal
gamemode=survival
EOF'

# Create CloudWatch agent configuration directory if it doesn't exist
sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/

# Create CloudWatch log groups
echo "Creating CloudWatch log groups..."
if aws logs create-log-group --log-group-name /minecraft/server-logs --region "$AWS_REGION" 2>/dev/null; then
    echo "✅ Created server logs group"
else
    echo "ℹ️ Server logs group already exists"
fi

if aws logs create-log-group --log-group-name /minecraft/voice-chat-logs --region "$AWS_REGION" 2>/dev/null; then
    echo "✅ Created voice chat logs group"
else
    echo "ℹ️ Voice chat logs group already exists"
fi

# Update CloudWatch agent configuration
echo "Updating CloudWatch agent configuration..."
sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > /dev/null << EOF
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
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "/minecraft/cloud-init",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/minecraft/system",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "$MINECRAFT_DIR/server/logs/latest.log",
            "log_group_name": "/minecraft/server-logs",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "$MINECRAFT_DIR/logs/voicechat.log",
            "log_group_name": "/minecraft/voice-chat-logs",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "swap": {
        "measurement": ["swap_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"]
      }
    },
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}"
    }
  }
}
EOF

# Create systemd service file
echo "Creating Minecraft service..."
sudo tee /etc/systemd/system/minecraft.service > /dev/null << EOF
[Unit]
Description=Minecraft NeoForge Server
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$MINECRAFT_DIR/server
Environment="JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto"
Environment="PATH=/usr/lib/jvm/java-21-amazon-corretto/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

# Restart policy
Restart=on-failure
RestartSec=30s

ExecStart=/usr/lib/jvm/java-21-amazon-corretto/bin/java -Xms2G -Xmx4G -jar neoforge-1.21.1.jar nogui
ExecStop=/usr/bin/bash -c 'echo "say SERVER SHUTTING DOWN IN 10 SECONDS..." > $MINECRAFT_DIR/server/console.pipe; sleep 10; echo "stop" > $MINECRAFT_DIR/server/console.pipe'
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Set correct permissions
sudo chmod 644 /etc/systemd/system/minecraft.service

# Allow user to manage the service
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart minecraft.service" | sudo tee /etc/sudoers.d/minecraft
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl start minecraft.service" | sudo tee -a /etc/sudoers.d/minecraft
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl stop minecraft.service" | sudo tee -a /etc/sudoers.d/minecraft
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl status minecraft.service" | sudo tee -a /etc/sudoers.d/minecraft
sudo chmod 440 /etc/sudoers.d/minecraft

# Start and enable CloudWatch agent
echo "Starting CloudWatch agent..."
sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl start amazon-cloudwatch-agent

# Reload systemd and enable service
echo "Enabling Minecraft service..."
sudo systemctl daemon-reload
sudo systemctl enable minecraft

echo "Instance setup completed successfully!" 