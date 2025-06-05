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
sudo mkdir -p /opt/minecraft/{server,mods,config,logs}

# Set permissions
echo "Setting permissions..."
sudo chown -R ec2-user:ec2-user /opt/minecraft
sudo chmod -R 755 /opt/minecraft

# Install NeoForge
echo "Installing NeoForge..."
cd /opt/minecraft/server

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
    echo "Failed to download NeoForge installer"
    exit 1
fi

if [ ! -f "/opt/minecraft/server/libraries/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-universal.jar" ]; then
    echo "Failed to download NeoForge universal JAR"
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
        echo "NeoForge installer failed with exit code $INSTALL_STATUS"
        echo "Installation log (last 10 lines):"
        tail -n 10 /opt/minecraft/logs/neoforge-install.log
        exit 1
    fi
fi

# List directory contents for debugging
echo "Contents of /opt/minecraft/server:"
ls -la /opt/minecraft/server

# Verify the installed JAR
NEOFORGE_JAR="/opt/minecraft/server/libraries/net/neoforged/neoforge/21.4.136/neoforge-21.4.136-server.jar"
if [ ! -f "$NEOFORGE_JAR" ]; then
    echo "Failed to install NeoForge. Server JAR not found at $NEOFORGE_JAR"
    echo "Installation log (last 10 lines):"
    tail -n 10 /opt/minecraft/logs/neoforge-install.log
    exit 1
fi

# Create a symlink to the server JAR
echo "Creating symlink to server JAR..."
sudo ln -sf "$NEOFORGE_JAR" "/opt/minecraft/server/neoforge-21.4.136.jar"

# Verify symlink was created
if [ ! -L "/opt/minecraft/server/neoforge-21.4.136.jar" ]; then
    echo "Failed to create symlink to NeoForge server JAR"
    exit 1
fi

echo "✅ NeoForge installation verified"

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