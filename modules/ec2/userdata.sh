#!/bin/bash

# Configurar logging del script de inicio
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "[$(date +%Y-%m-%d_%H:%M:%S)] Iniciando configuración del servidor Minecraft"

# Actualizar el sistema
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Actualizando el sistema..."
apt update && apt upgrade -y

# Instalar Java 21 (headless)
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Instalando Java 21..."
apt install openjdk-21-jdk-headless -y

# Instalar herramientas necesarias
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Instalando herramientas adicionales..."
apt install wget unzip htop -y

# Crear estructura de directorios
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Creando estructura de directorios..."
mkdir -p /opt/minecraft/server
mkdir -p /opt/minecraft/logs
mkdir -p /opt/minecraft/backups

# Crear usuario específico para Minecraft
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Creando usuario minecraft..."
useradd -r -m -U -d /opt/minecraft -s /bin/bash minecraft

# Configurar directorio de logs (logrotate)
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

# Script de inicio del servidor (simplificado)
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Creando script de inicio..."
cat > /opt/minecraft/server/start.sh << 'EOF'
#!/bin/bash

# Configuración de logging
LOG_DIR="/opt/minecraft/logs"
LATEST_LOG="${LOG_DIR}/latest.log"

# Crear directorio de logs si no existe
mkdir -p ${LOG_DIR}

# Función para logging
log() {
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] $1" | tee -a ${LATEST_LOG}
}

# Iniciar servidor con logging (ajustado para menos opciones)
log "Iniciando servidor Minecraft"
java -Xmx4G -Xms2G \
     -XX:+UseG1GC \
     -jar server.jar nogui \
     2>&1 | tee -a ${LATEST_LOG}

log "Servidor detenido"
EOF

# Dar permisos ejecutables al script
chmod +x /opt/minecraft/server/start.sh

# Ajustar permisos
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Ajustando permisos..."
chown -R minecraft:minecraft /opt/minecraft
chmod -R 755 /opt/minecraft

# Crear servicio systemd
echo "[$(date +%Y-%m-%d_%H:%M:%S)] Configurando servicio systemd..."
cat > /etc/systemd/system/minecraft.service << 'EOF'
[Unit]
Description=Minecraft Server
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

echo "[$(date +%Y-%m-%d_%H:%M:%S)] Configuración inicial completada"