#!/usr/bin/env bash
# ==============================================================================
# Script Name: instance_setup.sh
# Description: Idempotent setup script for Minecraft NeoForge Server on EC2.
#              Relies on the attached EC2 IAM Instance Profile (no static keys).
# ==============================================================================
set -euo pipefail

readonly MINECRAFT_DIR="/opt/minecraft"
readonly SERVER_DIR="${MINECRAFT_DIR}/server"
readonly NEOFORGE_VERSION="21.4.136"
readonly STAGE="${STAGE:-dev}"
readonly AWS_REGION="${AWS_REGION:-us-east-1}"
readonly GAME_PORT="${GAME_PORT:-25565}"
readonly SERVER_MEMORY="${SERVER_MEMORY:-2}"

cleanupOnExit() {
  rm -f "/tmp/neoforge-${NEOFORGE_VERSION}-installer.jar"
}
trap cleanupOnExit EXIT

ensureRoot() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Not running as root. Re-executing with sudo..."
    exec sudo -E bash "$0" "$@"
  fi
}

commandExists() {
  command -v "$1" >/dev/null 2>&1
}

getJavaMajorVersion() {
  java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1
}

installPackagesAndJava() {
  echo "Updating system packages and ensuring Amazon Corretto 21 is installed..."
  if commandExists dnf; then
    dnf update -y
    dnf install -y wget gnupg2 jq amazon-cloudwatch-agent java-21-amazon-corretto-headless
  else
    yum update -y
    yum install -y wget gnupg2 jq amazon-cloudwatch-agent
    if ! commandExists java || [ "$(getJavaMajorVersion)" != "21" ]; then
      rpm --import https://yum.corretto.aws/corretto.key
      curl -fsSL -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo
      yum install -y java-21-amazon-corretto-devel
    fi
  fi

  local installedVersion
  installedVersion=$(getJavaMajorVersion)
  if [ "$installedVersion" != "21" ]; then
    echo "::error::Failed to verify Java 21 installation (found: $installedVersion)" >&2
    exit 1
  fi
  echo "✅ Java 21 installed successfully"
}

setupDirectories() {
  echo "Creating Minecraft directory structure..."
  mkdir -p "${MINECRAFT_DIR}"/{server,mods,config,logs,backups}
  chown -R ec2-user:ec2-user "${MINECRAFT_DIR}"
  chmod -R 755 "${MINECRAFT_DIR}"
}

installNeoForge() {
  echo "Ensuring NeoForge ${NEOFORGE_VERSION} is installed..."
  cd "${SERVER_DIR}"

  if [ -f "${SERVER_DIR}/run.sh" ] || [ -f "${SERVER_DIR}/neoforge-${NEOFORGE_VERSION}.jar" ]; then
    echo "✅ NeoForge is already installed"
  else
    local installerPath="/tmp/neoforge-${NEOFORGE_VERSION}-installer.jar"
    sudo -u ec2-user wget -q -O "$installerPath" \
      "https://maven.neoforged.net/releases/net/neoforged/neoforge/${NEOFORGE_VERSION}/neoforge-${NEOFORGE_VERSION}-installer.jar"
    sudo -u ec2-user java -jar "$installerPath" --installServer "${SERVER_DIR}"
    echo "✅ NeoForge installation completed"
  fi

  sudo -u ec2-user bash -c "echo 'eula=true' > '${SERVER_DIR}/eula.txt'"
  sudo -u ec2-user bash -c "cat > '${SERVER_DIR}/server.properties' << EOF
server-port=${GAME_PORT}
max-players=20
difficulty=normal
gamemode=survival
EOF"
}

configureCloudWatch() {
  echo "Configuring CloudWatch Agent..."
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

  aws logs create-log-group --log-group-name "/minecraft/server/${STAGE}" --region "$AWS_REGION" 2>/dev/null || true
  aws logs create-log-group --log-group-name "/minecraft/voice-chat/${STAGE}" --region "$AWS_REGION" 2>/dev/null || true

  systemctl enable amazon-cloudwatch-agent
  systemctl restart amazon-cloudwatch-agent
}

configureSystemd() {
  echo "Configuring Minecraft systemd service..."
  local execStartCmd="/usr/bin/java -Xmx${SERVER_MEMORY}G -Xms${SERVER_MEMORY}G -jar neoforge-${NEOFORGE_VERSION}.jar nogui"
  if [ -f "${SERVER_DIR}/run.sh" ]; then
    chmod +x "${SERVER_DIR}/run.sh"
    echo "-Xmx${SERVER_MEMORY}G -Xms${SERVER_MEMORY}G" > "${SERVER_DIR}/user_jvm_args.txt"
    chown ec2-user:ec2-user "${SERVER_DIR}/user_jvm_args.txt"
    execStartCmd="/bin/bash ${SERVER_DIR}/run.sh nogui"
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
  systemctl restart minecraft
}

main() {
  ensureRoot "$@"
  installPackagesAndJava
  setupDirectories
  installNeoForge
  configureCloudWatch
  configureSystemd
  echo "Instance setup completed successfully!"
}

main "$@"
