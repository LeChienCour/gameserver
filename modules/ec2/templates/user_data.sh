#!/usr/bin/env bash
# ==============================================================================
# Script Name: user_data.sh
# Description: Bootstrap script for Minecraft NeoForge Server & CloudWatch Agent
# ==============================================================================
set -euo pipefail

readonly MINECRAFT_DIR="/opt/minecraft"
readonly SERVER_DIR="/opt/minecraft/server"
readonly LOG_FILE="/var/log/minecraft_bootstrap.log"
readonly GAME_PORT="${game_port}"
readonly STAGE="${stage}"
readonly SERVER_MEMORY="${server_memory}"
readonly NEOFORGE_VERSION="21.4.136"

# Redirect stdout and stderr to log file and console
exec > >(tee -a "$LOG_FILE") 2>&1

cleanupOnExit() {
  local exitCode=$?
  if [ "$exitCode" -ne 0 ]; then
    echo "[ERROR] Bootstrap failed with exit code $exitCode" >&2
  fi
  rm -f "/tmp/neoforge-${NEOFORGE_VERSION}-installer.jar"
}
trap cleanupOnExit EXIT

ensureRoot() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Re-executing script with sudo..."
    exec sudo -E bash "$0" "$@"
  fi
}

installPackages() {
  echo "Installing system packages and Java 21 (Amazon Corretto)..."
  if command -v dnf >/dev/null 2>&1; then
    dnf update -y
    dnf install -y wget jq amazon-cloudwatch-agent java-21-amazon-corretto-headless
  else
    yum update -y
    yum install -y wget jq amazon-cloudwatch-agent java-21-amazon-corretto-headless
  fi
}

setupDirectories() {
  echo "Creating Minecraft directory structure at $MINECRAFT_DIR..."
  mkdir -p "$MINECRAFT_DIR"/{server,mods,config,logs}
  chown -R ec2-user:ec2-user "$MINECRAFT_DIR"
  chmod -R 755 "$MINECRAFT_DIR"
}

installNeoForge() {
  echo "Setting up NeoForge $NEOFORGE_VERSION in $SERVER_DIR..."
  cd "$SERVER_DIR"

  local installerUrl="https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEOFORGE_VERSION}/neoforge-${NEOFORGE_VERSION}-installer.jar"
  local installerPath="/tmp/neoforge-${NEOFORGE_VERSION}-installer.jar"

  if [ ! -f "$SERVER_DIR/run.sh" ] && [ ! -f "$SERVER_DIR/server.jar" ]; then
    sudo -u ec2-user wget -q -O "$installerPath" "$installerUrl"
    sudo -u ec2-user java -jar "$installerPath" --installServer "$SERVER_DIR"
  fi

  echo "eula=true" > "$SERVER_DIR/eula.txt"
  cat > "$SERVER_DIR/server.properties" << EOF
server-port=${GAME_PORT}
max-players=20
difficulty=normal
gamemode=survival
EOF

  chown -R ec2-user:ec2-user "$SERVER_DIR"
}

configureCloudWatchAgent() {
  echo "Configuring Amazon CloudWatch Agent..."
  mkdir -p /opt/aws/amazon-cloudwatch-agent/etc

  cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
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
            "log_group_name": "/minecraft/server/${STAGE}",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/opt/minecraft/logs/voice-chat.log",
            "log_group_name": "/minecraft/voice-chat/${STAGE}",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

  systemctl enable amazon-cloudwatch-agent
  systemctl restart amazon-cloudwatch-agent
}

configureSystemdService() {
  echo "Creating systemd unit for Minecraft Server..."
  local execStartCmd="/usr/bin/java -Xmx${SERVER_MEMORY}G -Xms${SERVER_MEMORY}G -jar server.jar nogui"
  if [ -f "$SERVER_DIR/run.sh" ]; then
    chmod +x "$SERVER_DIR/run.sh"
    echo "-Xmx${SERVER_MEMORY}G -Xms${SERVER_MEMORY}G" > "$SERVER_DIR/user_jvm_args.txt"
    chown ec2-user:ec2-user "$SERVER_DIR/user_jvm_args.txt"
    execStartCmd="/bin/bash $SERVER_DIR/run.sh nogui"
  fi

  cat > /etc/systemd/system/minecraft.service << EOF
[Unit]
Description=Minecraft NeoForge Server (${STAGE})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=${SERVER_DIR}
ExecStart=${execStartCmd}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable minecraft
  systemctl start minecraft
}

main() {
  ensureRoot "$@"
  installPackages
  setupDirectories
  installNeoForge
  configureCloudWatchAgent
  configureSystemdService
  echo "Instance setup completed successfully!"
}

main "$@"
