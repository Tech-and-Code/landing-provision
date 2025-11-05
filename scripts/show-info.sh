#!/bin/bash

# Script para mostrar información de acceso a HouseUnity
# Ejecuta este script en cualquier momento para ver cómo acceder a tu aplicación

# Colores
RED='\033[1;31m'
GREEN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE='\033[1;36m'
NC='\033[0m'

# Función para imprimir mensajes
log() {
    echo -e "${GREEN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

info() {
    echo -e "${BLUE}$1${NC}"
}

error() {
    echo -e "${RED}$1${NC}"
}

# Banner
clear
echo ""
log "════════════════════════════════════════════════════════════════════"
log "           📱 INFORMACIÓN DE ACCESO - HOUSEUNITY 📱"
log "════════════════════════════════════════════════════════════════════"
echo ""

# Detectar IP de la VM
VM_IP=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$VM_IP" ]; then
    error "❌ No se pudo detectar la IP de la VM"
    VM_IP="<IP_DE_LA_VM>"
fi

log "🌐 IP de la VM: $VM_IP"
echo ""

# Buscar el directorio del proyecto
PROJECT_DIR=""
if [ -f ".provision.conf" ]; then
    PROJECT_DIR=$(grep "PROJECT_DIR=" .provision.conf | cut -d'"' -f2)
elif [ -d "$HOME/Tech-Code-Proyecto" ]; then
    PROJECT_DIR="$HOME/Tech-Code-Proyecto"
elif [ -d "$HOME/houseunity" ]; then
    PROJECT_DIR="$HOME/houseunity"
fi

# Detectar puertos del docker-compose.yml
BACKEND_PORT=8080
FRONTEND_PORT=5173
MYSQL_MASTER_PORT=3307
MYSQL_SLAVE_PORT=3308

if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    info "📂 Proyecto encontrado en: $PROJECT_DIR"
    
    # Intentar detectar puertos del docker-compose
    BACKEND_PORT=$(grep -A 5 "ports:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | grep -oP '"\K\d+(?=:)' | head -1 || echo "8080")
    FRONTEND_PORT=$(grep -A 5 "ports:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | grep -oP '"\K\d+(?=:)' | sed -n '2p' || echo "5173")
else
    warn "⚠️  No se encontró el directorio del proyecto. Usando puertos por defecto."
fi

echo ""
log "════════════════════════════════════════════════════════════════════"
log "              🌐 ACCESO A LA APLICACIÓN WEB"
log "════════════════════════════════════════════════════════════════════"
echo ""

# Detectar tipo de red
if [[ "$VM_IP" == 10.0.2.* ]]; then
    warn "⚠️  RED EN MODO NAT DETECTADA"
    echo ""
    warn "Para acceder desde Windows, necesitas configurar Port Forwarding:"
    echo ""
    info "1. Abre VirtualBox"
    info "2. Click derecho en tu VM → Settings → Network"
    info "3. Adapter 1 → Advanced → Port Forwarding"
    info "4. Agrega estas reglas:"
    echo ""
    echo "   ┌─────────────┬────────────┬────────────┬──────────────┬────────────┐"
    echo "   │ Nombre      │ Protocolo  │ Host IP    │ Host Port    │ Guest Port │"
    echo "   ├─────────────┼────────────┼────────────┼──────────────┼────────────┤"
    echo "   │ Backend     │ TCP        │ 127.0.0.1  │ $BACKEND_PORT      │ $BACKEND_PORT    │"
    echo "   │ Frontend    │ TCP        │ 127.0.0.1  │ $FRONTEND_PORT     │ $FRONTEND_PORT   │"
    echo "   │ MySQL       │ TCP        │ 127.0.0.1  │ $MYSQL_MASTER_PORT     │ $MYSQL_MASTER_PORT   │"
    echo "   │ SSH         │ TCP        │ 127.0.0.1  │ 2222         │ 22         │"
    echo "   └─────────────┴────────────┴────────────┴──────────────┴────────────┘"
    echo ""
    log "Después de configurar, accede con:"
    echo ""
    echo "   🌐 Backend API:     http://localhost:$BACKEND_PORT"
    echo "   🎨 Frontend:        http://localhost:$FRONTEND_PORT"
    echo "   🗄️  MySQL Master:    localhost:$MYSQL_MASTER_PORT"
    echo "   🔐 SSH:             ssh -p 2222 usuario@localhost"
    echo ""
else
    log "✅ RED EN MODO BRIDGE/HOST-ONLY - Acceso directo disponible"
    echo ""
    log "Desde Windows u otro PC en la misma red, abre tu navegador:"
    echo ""
    echo "   🌐 Backend API:     http://$VM_IP:$BACKEND_PORT"
    echo "   🎨 Frontend:        http://$VM_IP:$FRONTEND_PORT"
    echo ""
    log "Conexión a Base de Datos:"
    echo ""
    echo "   🗄️  MySQL Master:    $VM_IP:$MYSQL_MASTER_PORT"
    echo "   🗄️  MySQL Slave:     $VM_IP:$MYSQL_SLAVE_PORT"
    echo "   👤 Usuario:         root o houseunity_user"
    echo "   📝 Base de datos:   houseunity"
    echo ""
    log "Conexión SSH desde Windows (Git Bash o PowerShell):"
    echo ""
    echo "   🔐 ssh usuario@$VM_IP"
    echo ""
fi

echo ""
log "════════════════════════════════════════════════════════════════════"
log "              🐳 GESTIÓN DE CONTENEDORES DOCKER"
log "════════════════════════════════════════════════════════════════════"
echo ""

if [ -n "$PROJECT_DIR" ]; then
    info "📂 Navega al directorio del proyecto:"
    echo "   cd $PROJECT_DIR"
    echo ""
fi

log "🔧 Comandos Docker Compose útiles:"
echo ""
echo "   Ver estado de contenedores:"
echo "   └─ docker compose ps"
echo ""
echo "   Ver logs en tiempo real:"
echo "   └─ docker compose logs -f"
echo ""
echo "   Ver logs de un servicio específico:"
echo "   └─ docker compose logs -f backend"
echo "   └─ docker compose logs -f frontend"
echo "   └─ docker compose logs -f mysql-master"
echo ""
echo "   Reiniciar todos los servicios:"
echo "   └─ docker compose restart"
echo ""
echo "   Reiniciar un servicio específico:"
echo "   └─ docker compose restart backend"
echo ""
echo "   Detener todos los contenedores:"
echo "   └─ docker compose down"
echo ""
echo "   Levantar contenedores (modo background):"
echo "   └─ docker compose up -d"
echo ""
echo "   Reconstruir y levantar (después de cambios):"
echo "   └─ docker compose up --build -d"
echo ""
echo "   Ejecutar comandos dentro de un contenedor:"
echo "   └─ docker exec -it houseunity-backend bash"
echo "   └─ docker exec -it houseunity-mysql-master mysql -u root -p"
echo ""
echo "   Ver uso de recursos:"
echo "   └─ docker stats"
echo ""

log "════════════════════════════════════════════════════════════════════"
log "              🗄️  ACCESO A MYSQL"
log "════════════════════════════════════════════════════════════════════"
echo ""

log "🔹 Desde la VM (localhost):"
echo ""
echo "   Conectar a MySQL Master:"
echo "   └─ docker exec -it houseunity-mysql-master mysql -u root -p"
echo ""
echo "   Conectar a MySQL Slave:"
echo "   └─ docker exec -it houseunity-mysql-slave mysql -u root -p"
echo ""

log "🔹 Desde Windows con MySQL Workbench:"
echo ""
echo "   Connection Method: Standard (TCP/IP)"
if [[ "$VM_IP" == 10.0.2.* ]]; then
    echo "   Hostname: localhost"
    echo "   Port: $MYSQL_MASTER_PORT (después de configurar Port Forwarding)"
else
    echo "   Hostname: $VM_IP"
    echo "   Port: $MYSQL_MASTER_PORT"
fi
echo "   Username: root"
echo "   Password: [la que configuraste en .env]"
echo ""

log "🔹 Desde línea de comandos en Windows (si tienes MySQL client):"
echo ""
if [[ "$VM_IP" == 10.0.2.* ]]; then
    echo "   mysql -h localhost -P $MYSQL_MASTER_PORT -u root -p"
else
    echo "   mysql -h $VM_IP -P $MYSQL_MASTER_PORT -u root -p"
fi
echo ""

log "════════════════════════════════════════════════════════════════════"
log "              🔄 REPLICACIÓN MYSQL MASTER-SLAVE"
log "════════════════════════════════════════════════════════════════════"
echo ""

info "La aplicación usa replicación MySQL para alta disponibilidad:"
echo ""
echo "   📝 Master (Escritura):  Puerto $MYSQL_MASTER_PORT (houseunity-mysql-master)"
echo "   📖 Slave (Lectura):     Puerto $MYSQL_SLAVE_PORT (houseunity-mysql-slave)"
echo ""

if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker/scripts/check-replication.sh" ]; then
    log "Verificar estado de replicación:"
    echo "   cd $PROJECT_DIR/docker/scripts"
    echo "   ./check-replication.sh"
    echo ""
else
    log "Verificar estado de replicación manualmente:"
    echo "   docker exec -it houseunity-mysql-slave mysql -u root -p -e \"SHOW SLAVE STATUS\\G\""
    echo ""
fi

log "════════════════════════════════════════════════════════════════════"
log "              💾 SISTEMA DE RESPALDO (RSYNC)"
log "════════════════════════════════════════════════════════════════════"
echo ""

log "🔹 Configuración:"
echo ""
echo "   Directorio compartido:  /export"
echo "   Puerto rsync HOST:      873"
echo "   Puerto rsync Docker:    8873"
echo "   Usuario:                backupuser"
echo ""

log "🔹 Ver contraseña de rsync:"
echo "   sudo cat /etc/rsyncd.secrets"
echo ""

log "🔹 Sincronizar archivos DESDE la VM (en Windows/cliente):"
echo ""
echo "   1. Guardar contraseña en archivo:"
echo "      echo 'CONTRASEÑA' > rsync.pass"
echo "      chmod 600 rsync.pass"
echo ""
echo "   2. Sincronizar:"
if [[ "$VM_IP" == 10.0.2.* ]]; then
    echo "      rsync -av --port=873 --password-file=rsync.pass backupuser@localhost::backups ./backup-local/"
else
    echo "      rsync -av --port=873 --password-file=rsync.pass backupuser@$VM_IP::backups ./backup-local/"
fi
echo ""

log "🔹 Enviar archivos A la VM:"
echo ""
if [[ "$VM_IP" == 10.0.2.* ]]; then
    echo "   rsync -av --port=873 --password-file=rsync.pass ./mi-archivo.txt backupuser@localhost::backups"
else
    echo "   rsync -av --port=873 --password-file=rsync.pass ./mi-archivo.txt backupuser@$VM_IP::backups"
fi
echo ""

log "════════════════════════════════════════════════════════════════════"
log "              🔍 DEBUGGING Y DIAGNÓSTICO"
log "════════════════════════════════════════════════════════════════════"
echo ""

log "🔹 Verificar que los puertos están escuchando:"
echo "   ss -tulpn | grep -E '$BACKEND_PORT|$FRONTEND_PORT|$MYSQL_MASTER_PORT|$MYSQL_SLAVE_PORT|873|8873'"
echo ""

log "🔹 Probar backend desde la VM:"
echo "   curl http://localhost:$BACKEND_PORT"
echo ""

log "🔹 Ver contenedores en ejecución:"
echo "   docker ps"
echo ""

log "🔹 Inspeccionar un contenedor:"
echo "   docker inspect houseunity-backend"
echo ""

log "🔹 Ver redes Docker:"
echo "   docker network ls"
echo "   docker network inspect houseunity_network"
echo ""

log "🔹 Listar archivos en /export (respaldos):"
echo "   ls -lh /export"
echo ""

log "🔹 Ver uso de disco:"
echo "   df -h"
echo ""

log "🔹 Monitorear recursos del sistema:"
echo "   htop"
echo ""

log "════════════════════════════════════════════════════════════════════"
log "              📚 ARCHIVOS IMPORTANTES"
log "════════════════════════════════════════════════════════════════════"
echo ""

if [ -n "$PROJECT_DIR" ]; then
    echo "   📄 Configuración de entorno:     $PROJECT_DIR/.env"
    echo "   🐳 Docker Compose:               $PROJECT_DIR/docker-compose.yml"
    echo "   📋 Logs de Laravel:              $PROJECT_DIR/storage/logs/"
    echo "   🗂️  Archivos subidos:            $PROJECT_DIR/public/uploads/"
    echo "   🔧 Scripts de respaldo:          $PROJECT_DIR/docker/scripts/"
    echo "   📦 Backups:                      /export/"
    echo ""
else
    echo "   📄 Configuración de provisión:   .provision.conf"
    echo "   🔧 Script de provisión:          scripts/provision-houseunity.sh"
    echo "   📋 Este script:                  scripts/show-info.sh"
    echo ""
fi

log "════════════════════════════════════════════════════════════════════"
log "              🆘 SOLUCIÓN DE PROBLEMAS COMUNES"
log "════════════════════════════════════════════════════════════════════"
echo ""

warn "❓ No puedo acceder desde Windows"
echo ""
echo "   1. Verifica que los contenedores estén corriendo:"
echo "      docker compose ps"
echo ""
echo "   2. Verifica que los puertos estén escuchando:"
echo "      ss -tulpn | grep $BACKEND_PORT"
echo ""
if [[ "$VM_IP" == 10.0.2.* ]]; then
    echo "   3. Verifica Port Forwarding en VirtualBox"
    echo ""
fi
echo "   4. Verifica el firewall:"
echo "      sudo ufw status  # Ubuntu/Debian"
echo "      sudo firewall-cmd --list-all  # Rocky/CentOS"
echo ""
echo "   5. Prueba desde la VM primero:"
echo "      curl http://localhost:$BACKEND_PORT"
echo ""

warn "❓ Los contenedores no inician"
echo ""
echo "   1. Ver errores:"
echo "      docker compose logs"
echo ""
echo "   2. Reconstruir:"
echo "      docker compose down"
echo "      docker compose up --build -d"
echo ""
echo "   3. Ver espacio en disco:"
echo "      df -h"
echo ""

warn "❓ MySQL no acepta conexiones"
echo ""
echo "   1. Verificar que el contenedor está corriendo:"
echo "      docker ps | grep mysql"
echo ""
echo "   2. Ver logs de MySQL:"
echo "      docker logs houseunity-mysql-master"
echo ""
echo "   3. Esperar a que termine de inicializar (puede tomar 1-2 minutos)"
echo ""

warn "❓ Cambié código pero no se refleja"
echo ""
echo "   1. Reconstruir contenedores:"
echo "      docker compose up --build -d"
echo ""
echo "   2. Limpiar caché de Laravel (si aplica):"
echo "      docker exec -it houseunity-backend php artisan cache:clear"
echo "      docker exec -it houseunity-backend php artisan config:clear"
echo ""

log "════════════════════════════════════════════════════════════════════"
log "              📞 INFORMACIÓN ADICIONAL"
log "════════════════════════════════════════════════════════════════════"
echo ""

info "Para volver a ejecutar este script en cualquier momento:"
echo "   bash ~/scripts/show-info.sh"
echo ""
echo "   O si lo descargaste con el proyecto:"
echo "   bash scripts/show-info.sh"
echo ""

log "════════════════════════════════════════════════════════════════════"
log "                    ✅ FIN DE LA INFORMACIÓN"
log "════════════════════════════════════════════════════════════════════"
echo ""
