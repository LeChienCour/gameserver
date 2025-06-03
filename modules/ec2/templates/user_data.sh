#!/bin/bash
set -e

# Update system and install required packages
yum update -y
yum install -y amazon-cloudwatch-agent jq wget

# Install Amazon Corretto JDK 17
wget https://corretto.aws/downloads/latest/amazon-corretto-17-x64-linux-jdk.rpm
yum install -y ./amazon-corretto-17-x64-linux-jdk.rpm
rm -f amazon-corretto-17-x64-linux-jdk.rpm

# Create minecraft user and directory structure
useradd -r -m -U -d /opt/minecraft minecraft
mkdir -p /opt/minecraft/{server,backups,logs}
chown -R minecraft:minecraft /opt/minecraft

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
User=minecraft
Group=minecraft
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

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Enable Minecraft service (but don't start it yet as we need NeoForge installation)
systemctl enable minecraft

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${stage}-game-server --resource GameServerInstance --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) 