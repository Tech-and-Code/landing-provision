#!/bin/bash

#!/bin/bash

# Script para mostrar rutas de acceso directas para probar contenedores

# Colores
GREEN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
error() { echo -e "${RED}$1${NC}"; }

clear
echo ""
log "════════════════════════════════════════════════════════════════════"
log "         🧪 RUTAS PARA PROBAR CONTENEDORES - HOUSEUNITY"
log "════════════════════════════════════════════════════════════════════"
echo ""

# Detectar IP de la VM
VM_IP=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$VM_IP" ]; then
    error "❌ No se pudo detectar la IP de la VM"
    exit 1
fi

log "🌐 IP de la VM: $VM_IP"
echo ""

# Buscar directorio del proyecto
PROJECT_DIR=""
if [ -f ".provision.conf" ]; then
    PROJECT_DIR=$(grep "PROJECT_DIR=" .provision.conf | cut -d'"' -f2)
elif [ -d "$HOME/Tech-Code-Proyecto" ]; then
    PROJECT_DIR="$HOME/Tech-Code-Proyecto"
elif [ -d "$HOME/houseunity" ]; then
    PROJECT_DIR="$HOME/houseunity"
fi

# Detectar puertos
BACKEND_PORT=8080
FRONTEND_PORT=5173
MYSQL_MASTER=3307
MYSQL_SLAVE=3308

if [ -n "$PROJECT_DIR" ] && [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    BACKEND_PORT=$(grep -A 5 "ports:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | grep -oP '"\K\d+(?=:)' | head -1 || echo "8080")
    FRONTEND_PORT=$(grep -A 5 "ports:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | grep -oP '"\K\d+(?=:)' | sed -n '2p' || echo "5173")
fi

log "════════════════════════════════════════════════════════════════════"
log "              📋 RUTAS PARA PROBAR DESDE TU NAVEGADOR"
log "════════════════════════════════════════════════════════════════════"
echo ""

log "🌐 Backend API:"
echo "   http://$VM_IP:$BACKEND_PORT"
echo ""

log "🎨 Frontend:"
echo "   http://$VM_IP:$FRONTEND_PORT"
echo ""

log "════════════════════════════════════════════════════════════════════"
log "              🗄️  RUTAS PARA MYSQL (Workbench/Cliente)"
log "════════════════════════════════════════════════════════════════════"
echo ""

log "📝 MySQL Master (Escritura):"
echo "   Host: $VM_IP"
echo "   Port: $MYSQL_MASTER"
echo "   User: root"
echo ""

log "📖 MySQL Slave (Lectura):"
echo "   Host: $VM_IP"
echo "   Port: $MYSQL_SLAVE"
echo "   User: root"
echo ""

log "════════════════════════════════════════════════════════════════════"
log "              🧪 PRUEBAS DESDE LÍNEA DE COMANDOS"
log "════════════════════════════════════════════════════════════════════"
echo ""

log "Desde Windows PowerShell:"
echo ""
echo "   # Probar Backend"
echo "   curl http://$VM_IP:$BACKEND_PORT"
echo ""
echo "   # Probar Frontend"
echo "   curl http://$VM_IP:$FRONTEND_PORT"
echo ""
echo "   # Abrir en navegador"
echo "   start http://$VM_IP:$BACKEND_PORT"
echo "   start http://$VM_IP:$FRONTEND_PORT"
echo ""

log "Desde la VM (localhost):"
echo ""
echo "   # Probar Backend"
echo "   curl http://localhost:$BACKEND_PORT"
echo ""
echo "   # Probar Frontend"
echo "   curl http://localhost:$FRONTEND_PORT"
echo ""
echo "   # Conectar a MySQL Master"
echo "   docker exec -it houseunity-mysql-master mysql -u root -p"
echo ""
echo "   # Conectar a MySQL Slave"
echo "   docker exec -it houseunity-mysql-slave mysql -u root -p"
echo ""

log "════════════════════════════════════════════════════════════════════"
log "              ✅ VERIFICAR ESTADO DE CONTENEDORES"
log "════════════════════════════════════════════════════════════════════"
echo ""

if command -v docker &> /dev/null; then
    log "Estado actual de contenedores:"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -E "NAMES|houseunity" || warn "⚠️  No hay contenedores corriendo"
else
    error "❌ Docker no está disponible"
fi

echo ""
log "════════════════════════════════════════════════════════════════════"
echo ""


# Colores
GREEN='\033[1;36m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

log() { echo -e "${GREEN}$1${NC}"; }
warn() { echo -e "${YELLOW}$1${NC}"; }
error() { echo -e "${RED}$1${NC}"; }

clear
echo ""
log "════════════════════════════════════════════════════════════════════"
log "           📱 RUTAS DE ACCESO - HOUSEUNITY 📱"
log "════════════════════════════════════════════════════════════════════"
echo ""

# Detectar IP de la VM
VM_IP=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$VM_IP" ]; then
    error "❌ No se pudo detectar la IP de la VM"
    exit 1
fi

log "🌐 IP detectada: $VM_IP"
echo ""

# Buscar directorio del proyecto
PROJECT_DIR=""
if [ -f ".provision.conf" ]; then
    PROJECT_DIR=$(grep "PROJECT_DIR=" .provision.conf | cut -d'"' -f2)
elif [ -d "$HOME/Tech-Code-Proyecto" ]; then
    PROJECT_DIR="$HOME/Tech-Code-Proyecto"
elif [ -d "$HOME/houseunity" ]; then
    PROJECT_DIR="$HOME/houseunity"
fi

if [ -z "$PROJECT_DIR" ]; then
    warn "⚠️  Proyecto no encontrado. Verifica que esté clonado."
    exit 1
fi

log "📂 Proyecto: $PROJECT_DIR"
echo ""

# Detectar puertos
BACKEND_PORT=8080
FRONTEND_PORT=5173
MYSQL_MASTER=3307
MYSQL_SLAVE=3308

if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    BACKEND_PORT=$(grep -A 5 "ports:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | grep -oP '"\K\d+(?=:)' | head -1 || echo "8080")
    FRONTEND_PORT=$(grep -A 5 "ports:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | grep -oP '"\K\d+(?=:)' | sed -n '2p' || echo "5173")
fi

# Verificar servicios activos
log "🔍 Verificando servicios..."
echo ""

BACKEND_RUNNING=$(ss -tulpn 2>/dev/null | grep ":$BACKEND_PORT " | wc -l)
FRONTEND_RUNNING=$(ss -tulpn 2>/dev/null | grep ":$FRONTEND_PORT " | wc -l)
MYSQL_M_RUNNING=$(ss -tulpn 2>/dev/null | grep ":$MYSQL_MASTER " | wc -l)
MYSQL_S_RUNNING=$(ss -tulpn 2>/dev/null | grep ":$MYSQL_SLAVE " | wc -l)

# Mostrar URLs de acceso
log "════════════════════════════════════════════════════════════════════"
log "                    🌐 URLs DE ACCESO"
log "════════════════════════════════════════════════════════════════════"
echo ""

if [ "$BACKEND_RUNNING" -gt 0 ]; then
    log "✅ Backend API:"
    echo "   http://$VM_IP:$BACKEND_PORT"
else
    error "❌ Backend NO está corriendo en puerto $BACKEND_PORT"
fi
echo ""

if [ "$FRONTEND_RUNNING" -gt 0 ]; then
    log "✅ Frontend:"
    echo "   http://$VM_IP:$FRONTEND_PORT"
else
    error "❌ Frontend NO está corriendo en puerto $FRONTEND_PORT"
fi
echo ""

if [ "$MYSQL_M_RUNNING" -gt 0 ]; then
    log "✅ MySQL Master:"
    echo "   Host: $VM_IP"
    echo "   Port: $MYSQL_MASTER"
else
    error "❌ MySQL Master NO está corriendo en puerto $MYSQL_MASTER"
fi
echo ""

if [ "$MYSQL_S_RUNNING" -gt 0 ]; then
    log "✅ MySQL Slave:"
    echo "   Host: $VM_IP"
    echo "   Port: $MYSQL_SLAVE"
else
    warn "⚠️  MySQL Slave NO está corriendo en puerto $MYSQL_SLAVE"
fi

echo ""

log "════════════════════════════════════════════════════════════════════"
log "                    � RUTAS DEL SISTEMA"
log "════════════════════════════════════════════════════════════════════"
echo ""

log "Directorio del Proyecto:"
echo "   $PROJECT_DIR"
echo ""

log "Archivos clave:"
if [ -f "$PROJECT_DIR/.env" ]; then
    echo "   ✅ .env               → $PROJECT_DIR/.env"
else
    echo "   ❌ .env no encontrado"
fi

if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    echo "   ✅ docker-compose.yml → $PROJECT_DIR/docker-compose.yml"
else
    echo "   ❌ docker-compose.yml no encontrado"
fi

if [ -d "$PROJECT_DIR/storage/logs" ]; then
    echo "   ✅ Logs Laravel       → $PROJECT_DIR/storage/logs/"
else
    echo "   ⚠️  storage/logs no encontrado"
fi

if [ -d "$PROJECT_DIR/public/uploads" ]; then
    echo "   ✅ Uploads            → $PROJECT_DIR/public/uploads/"
else
    echo "   ⚠️  public/uploads no encontrado"
fi

if [ -d "/export" ]; then
    echo "   ✅ Backups (rsync)    → /export/"
else
    echo "   ⚠️  /export no encontrado"
fi

echo ""
log "════════════════════════════════════════════════════════════════════"
log "                    � ESTADO DE DOCKER"
log "════════════════════════════════════════════════════════════════════"
echo ""

if command -v docker &> /dev/null; then
    CONTAINERS=$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep houseunity)
    
    if [ -n "$CONTAINERS" ]; then
        log "Contenedores activos:"
        echo "$CONTAINERS"
    else
        warn "⚠️  No hay contenedores de HouseUnity corriendo"
        echo ""
        echo "Para iniciar:"
        echo "   cd $PROJECT_DIR"
        echo "   docker compose up -d"
    fi
else
    error "❌ Docker no está instalado o no está en PATH"
fi

echo ""
log "════════════════════════════════════════════════════════════════════"
echo ""

