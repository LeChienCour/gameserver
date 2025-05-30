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

# Stop the Minecraft service if running
echo "Stopping Minecraft server if running..."
sudo systemctl stop minecraft.service

# Download and install NeoForge if not already installed
if [ ! -f "/opt/minecraft/server/libraries/net/neoforged/forge/1.21.1/unix_args.txt" ]; then
  echo "Installing NeoForge..."
  cd /opt/minecraft/server
  
  wget -q https://maven.neoforged.net/releases/net/neoforged/neoforge/1.21.1/neoforge-1.21.1-installer.jar
  java -jar neoforge-1.21.1-installer.jar --installServer
  
  # Accept EULA
  echo "eula=true" > eula.txt
  
  # Basic server configuration
  cat > server.properties << 'EOFINNER'
server-port=25565
max-players=20
difficulty=normal
gamemode=survival
EOFINNER
fi

# Update mod files
echo "Updating mod..."
cd /opt/minecraft/server
mkdir -p mods
rm -f mods/*.jar
cp "build/libs/voicechatmod-0.0.1.jar" mods/

# Ensure correct permissions
sudo chown -R minecraft:minecraft /opt/minecraft/server/mods

# Rotate logs
echo "Rotating logs..."
if [ -f "logs/latest.log" ]; then
  mv logs/latest.log "logs/previous-$(date +%Y%m%d-%H:%M:%S).log"
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