#!/usr/bin/env bash
# ==============================================================================
# Script Name: user_data.sh
# Description: Bootstrap script for Minecraft NeoForge Server, CloudWatch Agent,
#              and automated S3 world backup timer.
# ==============================================================================
set -euo pipefail

readonly MINECRAFT_DIR="/opt/minecraft"
readonly SERVER_DIR="/opt/minecraft/server"
readonly LOG_FILE="/var/log/minecraft_bootstrap.log"
readonly GAME_PORT="${game_port}"
readonly STAGE="${stage}"
readonly SERVER_MEMORY="${server_memory}"
readonly AUDIO_BUCKET_NAME="${audio_bucket_name}"
readonly NEOFORGE_VERSION="21.4.136"

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
    dnf install -y wget jq tar gzip awscli amazon-cloudwatch-agent java-21-amazon-corretto-headless
  else
    yum update -y
    yum install -y wget jq tar gzip awscli amazon-cloudwatch-agent java-21-amazon-corretto-headless
  fi
}

setupDirectories() {
  echo "Creating Minecraft directory structure at $MINECRAFT_DIR..."
  mkdir -p "$MINECRAFT_DIR"/{server,mods,config,logs,backups}
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

configureWorldBackupTimer() {
  echo "Configuring automated S3 world backup script and systemd timer..."
  cat > /usr/local/bin/backup_minecraft_world.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

readonly SERVER_DIR="/opt/minecraft/server"
readonly BACKUP_DIR="/opt/minecraft/backups"
readonly BUCKET_NAME="${1:-}"
readonly STAGE_NAME="${2:-dev}"

if [ ! -d "${SERVER_DIR}/world" ]; then
  echo "No world directory found yet; skipping backup."
  exit 0
fi

timestamp=$(date -u +"%Y%m%d_%H%M%S")
archivePath="${BACKUP_DIR}/world_${STAGE_NAME}_${timestamp}.tar.gz"

tar -czf "$archivePath" -C "$SERVER_DIR" world

if [ -n "$BUCKET_NAME" ]; then
  aws s3 cp "$archivePath" "s3://${BUCKET_NAME}/backups/${STAGE_NAME}/world_${timestamp}.tar.gz"
fi

# Retain only the 3 most recent local archives
find "$BACKUP_DIR" -name "world_*.tar.gz" -type f -mtime +2 -delete || true
EOF
  chmod +x /usr/local/bin/backup_minecraft_world.sh

  cat > /etc/systemd/system/minecraft-backup.service << EOF
[Unit]
Description=Minecraft World Backup to S3 (${STAGE})

[Service]
Type=oneshot
User=ec2-user
ExecStart=/usr/local/bin/backup_minecraft_world.sh "${AUDIO_BUCKET_NAME}" "${STAGE}"
EOF

  cat > /etc/systemd/system/minecraft-backup.timer << 'EOF'
[Unit]
Description=Run Minecraft World Backup every 6 hours

[Timer]
OnCalendar=*-*-* 00/6:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable minecraft-backup.timer
  systemctl start minecraft-backup.timer
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
  configureWorldBackupTimer
  configureCloudWatchAgent
  configureSystemdService
  echo "Instance setup completed successfully!"
}

main "$@"
