#!/bin/bash
set -e

# Update system and install required packages
yum update -y
yum install -y amazon-cloudwatch-agent jq wget

# Install Amazon Corretto JDK 17
wget https://corretto.aws/downloads/latest/amazon-corretto-17-x64-linux-jdk.rpm
yum install -y ./amazon-corretto-17-x64-linux-jdk.rpm
rm -f amazon-corretto-17-x64-linux-jdk.rpm

# Create minecraft directory structure and set permissions
mkdir -p /opt/minecraft/{server,backups,logs}

# Set ownership to ec2-user for deployment access
chown -R ec2-user:ec2-user /opt/minecraft

# Install NeoForge
cd /opt/minecraft/server
wget -q https://maven.neoforged.net/releases/net/neoforged/neoforge/1.21.1/neoforge-1.21.1-installer.jar
sudo -u ec2-user java -jar neoforge-1.21.1-installer.jar --installServer
rm -f neoforge-1.21.1-installer.jar

# Accept EULA and create basic server configuration
sudo -u ec2-user bash -c 'echo "eula=true" > eula.txt'
sudo -u ec2-user bash -c 'cat > server.properties << EOF
server-port=${game_port}
max-players=20
difficulty=normal
gamemode=survival
EOF'

# Configure environment variables
cat > /etc/environment <<EOF
GAME_PORT=${game_port}
WEBSOCKET_PORT=${websocket_port}
USER_POOL_ID=${user_pool_id}
USER_POOL_CLIENT_ID=${user_pool_client_id}
STAGE=${stage}
ENVIRONMENT=${environment}
JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto
PATH=$PATH:/usr/lib/jvm/java-17-amazon-corretto/bin
EOF

# Set up CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
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
            "log_group_name": "/game-server/${stage}/cloud-init",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/game-server/${stage}/system",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "/opt/minecraft/server/logs/latest.log",
            "log_group_name": "/game-server/${stage}/minecraft",
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

# Create systemd service for Minecraft
cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=Minecraft NeoForge Server
After=network.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/opt/minecraft/server
Environment="JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto"
Environment="PATH=/usr/lib/jvm/java-17-amazon-corretto/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

# Read environment variables
EnvironmentFile=/etc/environment

# Restart policy
Restart=on-failure
RestartSec=30s

ExecStart=/usr/lib/jvm/java-17-amazon-corretto/bin/java -Xms2G -Xmx4G -jar neoforge-1.21.1.jar nogui
ExecStop=/usr/bin/bash -c 'echo "say SERVER SHUTTING DOWN IN 10 SECONDS..." > /opt/minecraft/server/console.pipe; sleep 10; echo "stop" > /opt/minecraft/server/console.pipe'
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Set correct permissions
chmod 644 /etc/systemd/system/minecraft.service

# Allow ec2-user to manage the service
echo "ec2-user ALL=(ALL) NOPASSWD: /bin/systemctl restart minecraft.service" > /etc/sudoers.d/minecraft
echo "ec2-user ALL=(ALL) NOPASSWD: /bin/systemctl start minecraft.service" >> /etc/sudoers.d/minecraft
echo "ec2-user ALL=(ALL) NOPASSWD: /bin/systemctl stop minecraft.service" >> /etc/sudoers.d/minecraft
echo "ec2-user ALL=(ALL) NOPASSWD: /bin/systemctl status minecraft.service" >> /etc/sudoers.d/minecraft
chmod 440 /etc/sudoers.d/minecraft

# Create mods directory
sudo -u ec2-user mkdir -p /opt/minecraft/server/mods

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Enable and start Minecraft service
systemctl enable minecraft
systemctl start minecraft

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${stage}-game-server --resource GameServerInstance --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 