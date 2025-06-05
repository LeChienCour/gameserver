#!/bin/bash
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Not running as root. Re-executing with sudo..."
  exec sudo -E bash "$0" "$@"
fi

# Check if AWS credentials are set
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_REGION" ]; then
  echo "::error::AWS credentials are required. Please set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_REGION"
  exit 1
fi

echo "Starting instance setup..."

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

# Create Minecraft directory structure
echo "Creating Minecraft directory structure..."
sudo mkdir -p /opt/minecraft/{server,mods,config,logs}

# Set permissions
echo "Setting permissions..."
sudo chown -R ec2-user:ec2-user /opt/minecraft
sudo chmod -R 755 /opt/minecraft

# Install NeoForge
echo "Installing NeoForge..."
cd /opt/minecraft/server

# Check if NeoForge is already installed
NEOFORGE_JAR="/opt/minecraft/server/libraries/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-server.jar"
if [ -f "$NEOFORGE_JAR" ] && [ -L "/opt/minecraft/server/neoforge-21.4.136.jar" ]; then
    echo "✅ NeoForge is already installed"
else
    # Ensure proper permissions and create necessary directories
    echo "Setting up directories and permissions..."
    sudo mkdir -p /opt/minecraft/server/libraries/net/neoforged/neoforge/21.4.136
    sudo mkdir -p /opt/minecraft/server/libraries/net/neoforged/neoform/1.21.4-20241203.161809
    sudo chown -R ec2-user:ec2-user /opt/minecraft/server
    sudo chmod -R 755 /opt/minecraft/server

    # Download NeoForge installer and universal JAR
    echo "Downloading NeoForge files..."
    sudo -u ec2-user wget -v https://maven.neoforged.net/releases/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-installer.jar
    sudo -u ec2-user wget -v https://maven.neoforged.net/releases/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-universal.jar -O /opt/minecraft/server/libraries/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-universal.jar

    # Verify files were downloaded
    if [ ! -f "neoforge-21.4.136-installer.jar" ]; then
        echo "::error::Failed to download NeoForge installer"
        exit 1
    fi

    if [ ! -f "/opt/minecraft/server/libraries/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-universal.jar" ]; then
        echo "::error::Failed to download NeoForge universal JAR"
        exit 1
    fi

    echo "Running NeoForge installer..."
    # Run installer and capture both stdout and stderr
    sudo -u ec2-user java -jar neoforge-21.4.136-installer.jar --installServer 2>&1 | tee /opt/minecraft/logs/neoforge-install.log

    # Check installer exit status
    INSTALL_STATUS=${PIPESTATUS[0]}
    if [ $INSTALL_STATUS -ne 0 ]; then
        # Check for the success message in the log
        if grep -q "The server installed successfully" /opt/minecraft/logs/neoforge-install.log; then
            echo "NeoForge installer exited with code $INSTALL_STATUS but reports success. Continuing."
        else
            echo "::error::NeoForge installer failed with exit code $INSTALL_STATUS"
            echo "::error::Installation log (last 10 lines):"
            tail -n 10 /opt/minecraft/logs/neoforge-install.log
            exit 1
        fi
    fi

    # List directory contents for debugging
    echo "Contents of /opt/minecraft/server:"
    ls -la /opt/minecraft/server

    # Verify the installed JAR
    if [ ! -f "$NEOFORGE_JAR" ]; then
        echo "::error::Failed to install NeoForge. Server JAR not found at $NEOFORGE_JAR"
        echo "::error::Installation log (last 10 lines):"
        tail -n 10 /opt/minecraft/logs/neoforge-install.log
        exit 1
    fi

    # Create a symlink to the server JAR
    echo "Creating symlink to server JAR..."
    ln -sf "$NEOFORGE_JAR" "/opt/minecraft/server/neoforge-21.4.136.jar"

    # Verify symlink was created
    if [ ! -L "/opt/minecraft/server/neoforge-21.4.136.jar" ]; then
        echo "::error::Failed to create symlink to NeoForge server JAR"
        exit 1
    fi

    echo "✅ NeoForge installation verified"

    # Clean up installer
    sudo -u ec2-user rm -f neoforge-21.4.136-installer.jar
fi

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

# Create CloudWatch log groups if they don't exist
echo "Creating CloudWatch log groups..."
aws logs create-log-group --log-group-name /minecraft/server-logs --region "$AWS_REGION" || true
aws logs create-log-group --log-group-name /minecraft/voice-chat-logs --region "$AWS_REGION" || true

# Create SSM parameters if they don't exist
echo "Creating SSM parameters..."
aws ssm put-parameter \
    --name "/minecraft/websocket-url" \
    --value "wss://7vy8tzmldf.execute-api.us-east-1.amazonaws.com/test" \
    --type "SecureString" \
    --region "$AWS_REGION" \
    --overwrite || true

aws ssm put-parameter \
    --name "/minecraft/websocket-api-key" \
    --value "m9iiSebJTW58OkyKtwJej1CxmUhmLbaVapAulxTg" \
    --type "SecureString" \
    --region "$AWS_REGION" \
    --overwrite || true

aws ssm put-parameter \
    --name "/minecraft/user-pool-id" \
    --value "us-east-1_OaKjZe6Ce" \
    --type "SecureString" \
    --region "$AWS_REGION" \
    --overwrite || true

aws ssm put-parameter \
    --name "/minecraft/user-pool-client-id" \
    --value "4f0iqtnsjiklmtat7k5ef8jaok" \
    --type "SecureString" \
    --region "$AWS_REGION" \
    --overwrite || true

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