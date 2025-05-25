#!/bin/bash

# Configurar logging del script de inicio
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "[$(date +%Y-%m-%d_%H:%M:%S)] Iniciando configuración del servidor Minecraft + NeoForge"

# Actualizar el sistema
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Actualizando el sistema..."
apt update && apt upgrade -y

# Instalar Java 21
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Instalando Java 21..."
apt install openjdk-21-jdk -y

# Instalar herramientas necesarias
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Instalando herramientas adicionales..."
apt install screen wget unzip htop -y

# Crear estructura de directorios
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Creando estructura de directorios..."
mkdir -p /opt/minecraft/server
mkdir -p /opt/minecraft/logs
mkdir -p /opt/minecraft/backups

# Crear usuario específico para Minecraft
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Creando usuario minecraft..."
useradd -r -m -U -d /opt/minecraft -s /bin/bash minecraft

# Configurar directorio de logs
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Configurando sistema de logs..."
cat > /etc/logrotate.d/minecraft << 'EOF'
/opt/minecraft/logs/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0644 minecraft minecraft
}
EOF

# Script de inicio del servidor
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Creando script de inicio..."
cat > /opt/minecraft/server/start.sh << 'EOF'
#!/bin/bash

# Configuración de logging
LOG_DIR="/opt/minecraft/logs"
LATEST_LOG="${LOG_DIR}/latest.log"
DEBUG_LOG="${LOG_DIR}/debug.log"
ERROR_LOG="${LOG_DIR}/errors.log"

# Crear directorio de logs si no existe
mkdir -p ${LOG_DIR}

# Función para logging
log() {
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] $1" | tee -a ${DEBUG_LOG}
}

# Monitoreo de errores en segundo plano
monitor_errors() {
    tail -f ${LATEST_LOG} | while read line; do
        if echo "$line" | grep -iE "error|exception|crash|fatal" > /dev/null; then
            echo "[$(date +%Y-%m-%d_%H:%M:%S)] $line" >> ${ERROR_LOG}
        fi
    done
}

# Iniciar monitoreo de errores en segundo plano
monitor_errors &

# Iniciar servidor con logging
log "Iniciando servidor Minecraft + NeoForge"
java -Xmx4G -Xms2G \
     -XX:+UseG1GC \
     -XX:+ParallelRefProcEnabled \
     -XX:MaxGCPauseMillis=200 \
     -XX:+UnlockExperimentalVMOptions \
     -XX:+DisableExplicitGC \
     -XX:+AlwaysPreTouch \
     -XX:G1NewSizePercent=30 \
     -XX:G1MaxNewSizePercent=40 \
     -XX:G1HeapRegionSize=8M \
     -XX:G1ReservePercent=20 \
     -XX:G1HeapWastePercent=5 \
     -XX:G1MixedGCCountTarget=4 \
     -XX:InitiatingHeapOccupancyPercent=15 \
     -XX:G1MixedGCLiveThresholdPercent=90 \
     -XX:G1RSetUpdatingPauseTimePercent=5 \
     -XX:SurvivorRatio=32 \
     -XX:+PerfDisableSharedMem \
     -XX:MaxTenuringThreshold=1 \
     -jar server.jar nogui \
     2>&1 | tee -a ${LATEST_LOG}

log "Servidor detenido"
EOF

# Dar permisos ejecutables al script
chmod +x /opt/minecraft/server/start.sh

# Descargar NeoForge
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Descargando NeoForge..."
cd /opt/minecraft/server
wget https://maven.neoforged.net/releases/net/neoforged/neoforge/1.21.1/neoforge-1.21.1-installer.jar

# Instalar NeoForge
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Instalando NeoForge..."
java -jar neoforge-1.21.1-installer.jar --installServer

# Ajustar permisos
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Ajustando permisos..."
chown -R minecraft:minecraft /opt/minecraft
chmod -R 755 /opt/minecraft

# Crear servicio systemd
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Configurando servicio systemd..."
cat > /etc/systemd/system/minecraft.service << 'EOF'
[Unit]
Description=Minecraft NeoForge Server
After=network.target

[Service]
Type=simple
User=minecraft
WorkingDirectory=/opt/minecraft/server
ExecStart=/opt/minecraft/server/start.sh
Restart=on-failure
RestartSec=60s

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar el servicio
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Habilitando servicio..."
systemctl enable minecraft.service
systemctl start minecraft.service

echo "[$(date +%Y-%m-%d_%H:%M:%S)] Configuración completada" 