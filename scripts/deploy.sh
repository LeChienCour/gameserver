#!/bin/bash
set -e

echo "Starting Minecraft server deployment..."

# Function to safely truncate logs
truncate_log() {
  local log_file=$1
  local max_lines=100
  if [ -f "$log_file" ]; then
    local total_lines=$(wc -l < "$log_file")
    if [ $total_lines -gt $max_lines ]; then
      echo "Log file has $total_lines lines, truncating to last $max_lines lines"
      tail -n $max_lines "$log_file" > "${log_file}.tmp"
      mv "${log_file}.tmp" "$log_file"
    fi
  fi
}

# Check if Minecraft is installed
if [ ! -d "/opt/minecraft/server" ]; then
  echo "Installing Minecraft server..."
  sudo mkdir -p /opt/minecraft/server
  sudo chown -R ubuntu:ubuntu /opt/minecraft
  cd /opt/minecraft/server
  
  echo "Downloading NeoForge..."
  wget -q https://maven.neoforged.net/releases/net/neoforged/neoforge/1.21.1/neoforge-1.21.1-installer.jar
  
  echo "Installing NeoForge..."
  java -jar neoforge-1.21.1-installer.jar --installServer
  
  echo "Configuring server..."
  echo "eula=true" > eula.txt
  cat > server.properties << 'EOFINNER'
server-port=25565
max-players=20
difficulty=normal
gamemode=survival
EOFINNER
  
  echo "Setting up systemd service..."
  sudo tee /etc/systemd/system/minecraft.service << 'EOFINNER'
[Unit]
Description=Minecraft Server
After=network.target

[Service]
WorkingDirectory=/opt/minecraft/server
User=ubuntu
Group=ubuntu
ExecStart=/bin/sh -c 'java -Xmx2G -Xms1G @user_jvm_args.txt @libraries/net/neoforged/forge/1.21.1/unix_args.txt nogui'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOFINNER
  
  sudo systemctl daemon-reload
  sudo systemctl enable minecraft.service
fi

cd /opt/minecraft/server

echo "Stopping Minecraft server if running..."
sudo systemctl stop minecraft.service

echo "Updating mod..."
mkdir -p mods
rm -f mods/*.jar
cp "build/libs/voicechatmod-0.0.1.jar" mods/

echo "Rotating logs..."
if [ -f "logs/latest.log" ]; then
  mv logs/latest.log "logs/previous-$(date +%Y%m%d-%H%M%S).log"
fi

echo "Starting Minecraft server..."
sudo systemctl start minecraft.service

echo "Monitoring server startup..."
touch /tmp/minecraft_startup.log
timeout 120 tail -f logs/latest.log | while read line; do
  echo "$line" >> /tmp/minecraft_startup.log
  if echo "$line" | grep -q "Done"; then
    pkill -P $$ tail
    exit 0
  fi
done

if grep -q "Done" /tmp/minecraft_startup.log; then
  if systemctl is-active --quiet minecraft.service; then
    echo "Server started successfully!"
    truncate_log /tmp/minecraft_startup.log
    echo "::set-output name=status::success"
    echo "::set-output name=message::Server running successfully with mod deployed"
    tail -n 10 /tmp/minecraft_startup.log
  else
    echo "::error::Service not running despite successful startup"
    exit 1
  fi
else
  echo "::error::Server failed to start within timeout"
  tail -n 50 /tmp/minecraft_startup.log
  exit 1
fi 