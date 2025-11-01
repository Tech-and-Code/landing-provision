#!/bin/bash

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Nombre del archivo de configuración del script
CONFIG_FILE=".provision.conf"

# Función para imprimir mensajes
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Función para verificar si el usuario tiene privilegios de sudo
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if ! command -v sudo &> /dev/null; then
            error "No eres root y el comando 'sudo' no está disponible. En Debian/Ubuntu, puedes instalarlo con: su -c 'apt-get update && apt-get install sudo -y'"
        fi
        
        if ! sudo -n true 2>/dev/null; then
            error "Este script requiere privilegios de sudo. Por favor ejecuta con sudo o como root."
        fi
    fi
}

# Función para cargar la configuración y solicitar valores faltantes al usuario
load_or_prompt_config() {
    info "Cargando configuración desde $CONFIG_FILE (si existe)..."
    if [ -f "$CONFIG_FILE" ]; then
        source <(grep -E '^[A-Z_]+=' "$CONFIG_FILE" | sed 's/^export //')
    else
        warn "Archivo de configuración $CONFIG_FILE no encontrado. Se solicitará la información."
    fi

    # 1. Definir el ambiente (dev/prod)
    while [ -z "$ENV_MODE" ]; do
        read -r -p "Introduce el ambiente a construir (dev o prod): [dev] " input_env
        ENV_MODE=${input_env:-dev}
        if [[ "$ENV_MODE" =~ ^(dev|prod)$ ]]; then
            break
        else
            warn "Valor inválido. Por favor, introduce 'dev' o 'prod'."
            ENV_MODE=""
        fi
    done
    
    # 2. Solicitar URL del repositorio
    while [ -z "$REPO_URL" ]; do
        read -r -p "Introduce la URL SSH de tu repositorio GitHub (ej: git@github.com:Tech-and-Code/Tech-Code-Proyecto.git): " REPO_URL
        if [ -z "$REPO_URL" ]; then
            warn "La URL del repositorio es obligatoria."
        fi
    done
    
    # Intentar obtener el nombre del proyecto desde la URL
    REPO_NAME=$(basename "$REPO_URL" .git)
    DEFAULT_DIR="$HOME/$REPO_NAME"

    # 3. Definir el directorio de instalación
    while [ -z "$PROJECT_DIR" ]; do
        read -r -p "Introduce el directorio de instalación: [$DEFAULT_DIR] " input_dir
        PROJECT_DIR=${input_dir:-$DEFAULT_DIR}
        if [ -z "$PROJECT_DIR" ]; then
             warn "El directorio de proyecto es obligatorio."
        fi
    done
    
    # 4. Guardar la configuración para la próxima vez
    log "Guardando configuración en $CONFIG_FILE..."
    {
        echo "REPO_URL=\"$REPO_URL\""
        echo "PROJECT_DIR=\"$PROJECT_DIR\""
        echo "ENV_MODE=\"$ENV_MODE\""
    } > "$CONFIG_FILE"
}

# Función para detectar la distribución de Linux
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID 
        OS_VERSION=$VERSION_ID
    else
        error "No se pudo detectar la distribución de Linux"
    fi
}

# Función para actualizar el sistema
update_system() {
    case "$OS" in
        ubuntu|debian)
            log "Actualizando repositorios del sistema..."
            sudo apt-get update -qq
            
            if [ "$ENV_MODE" = "prod" ]; then
                log "Actualizando todos los paquetes..."
                sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
            else
                log "Actualizando paquetes críticos..."
                sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq --with-new-pkgs
            fi
            ;;
        centos|rhel|fedora|rocky)
            # Optimizar DNF para Rocky Linux
            log "Configurando DNF..."
            if ! grep -q "fastestmirror=True" /etc/dnf/dnf.conf 2>/dev/null; then
                echo "fastestmirror=True" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
                echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
                echo "deltarpm=True" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
            fi
            
            # Limpiar caché viejo
            sudo dnf clean all > /dev/null 2>&1 || true
            
            if [ "$ENV_MODE" = "prod" ]; then
                log "Actualizando sistema completo..."
                sudo dnf update -y --nobest --skip-broken
            else
                log "Actualizando paquetes críticos..."
                sudo dnf update -y --security --nobest 2>&1 | grep -E "Upgrading|Installing|Complete|Nothing" || true
            fi
            ;;
        *)
            error "Sistema operativo no soportado: $OS"
            ;;
    esac
    
    log "✓ Sistema actualizado correctamente"
}

# Función para instalar paquetes básicos
install_basic_tools() {
    log "Instalando herramientas básicas..."
    case "$OS" in
        ubuntu|debian)
            sudo apt-get install -y -qq git curl wget rsync openssh-client openssh-server \
                software-properties-common apt-transport-https ca-certificates \
                gnupg-agent unzip make nano htop tree net-tools 
            ;;
        centos|rhel|fedora|rocky)
            # Habilitar EPEL para Rocky Linux/RHEL
            if [[ "$OS" == "rocky" || "$OS" == "rhel" ]]; then
                log "Habilitando repositorio EPEL..."
                sudo dnf install -y epel-release || warn "No se pudo instalar EPEL, continuando..."
            fi
            
            # Instalar paquetes básicos
            log "Instalando paquetes esenciales..."
            sudo dnf install -y git curl wget rsync openssh-clients openssh-server \
                unzip nano vim make tree net-tools || warn "Algunos paquetes básicos fallaron, continuando..."
            
            # Intentar instalar htop (puede fallar si EPEL no está disponible)
            log "Instalando htop..."
            sudo dnf install -y htop || warn "htop no disponible, continuando sin él..."
            ;;
        *)
            error "Sistema operativo no soportado para la instalación de herramientas básicas: $OS"
            ;;
    esac
    
    log "✓ Herramientas básicas instaladas"
}

# Función para instalar Docker y el plugin de Docker Compose
install_docker() {
    log "Instalando Docker Engine y el plugin de Docker Compose (v2)..."
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        warn "Docker y Docker Compose (plugin) ya están instalados"
        return
    fi

    case "$OS" in
        ubuntu)
            sudo apt-get update -qq
            sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        debian)
            sudo apt-get update -qq
            sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
            sudo install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            sudo chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        centos|rhel|fedora|rocky)
            if [ "$OS" == "fedora" ]; then
                sudo dnf -y install dnf-plugins-core
                sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            else
                sudo dnf install -y dnf-plugins-core
                sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
        *)
            error "Sistema operativo no soportado para la instalación de Docker: $OS"
            ;;
    esac

    if [ -n "$USER" ] && ! id -nG "$USER" | grep -qw "docker"; then
        log "Agregando usuario '$USER' al grupo 'docker'. Necesitarás cerrar sesión y volver a entrar."
        sudo usermod -aG docker "$USER"
    fi
    
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log "Docker instalado correctamente"
}

# Función para instalar Docker Compose Standalone
install_docker_compose() {
    log "Instalando Docker Compose Standalone (v2) para compatibilidad con 'docker-compose'..."
    if command -v docker-compose &> /dev/null; then
        warn "El binario 'docker-compose' ya está instalado. Omitiendo instalación."
        return
    fi
    
    local COMPOSE_VERSION="v2.23.0"
    log "Descargando Docker Compose Standalone versión $COMPOSE_VERSION..."
    
    if ! sudo curl -L "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose --silent; then
        error "Fallo al descargar Docker Compose Standalone v2."
    fi
    
    sudo chmod +x /usr/local/bin/docker-compose
    
    if [ ! -f /usr/bin/docker-compose ]; then
        log "Creando enlace simbólico: /usr/bin/docker-compose -> /usr/local/bin/docker-compose"
        sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    fi
    
    log "Docker Compose Standalone (v2) instalado correctamente como 'docker-compose'"
}

# Función para configurar SSH
setup_ssh() {
    local SSH_CONFIG="/etc/ssh/sshd_config"
    local SSH_CONFIG_BACKUP="${SSH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

    log "Configurando SSH..."
    
    if [ -f "$SSH_CONFIG" ]; then
        log "Respaldando $SSH_CONFIG a $SSH_CONFIG_BACKUP"
        sudo cp "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"
    fi

    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    sudo sed -i -E 's/^\s*#?PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
    if ! grep -q '^PermitRootLogin' "$SSH_CONFIG"; then
        echo "PermitRootLogin no" | sudo tee -a "$SSH_CONFIG" > /dev/null
    fi

    sudo sed -i -E 's/^\s*#?PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
    if ! grep -q '^PasswordAuthentication' "$SSH_CONFIG"; then
        echo "PasswordAuthentication no" | sudo tee -a "$SSH_CONFIG" > /dev/null
    fi
    
    log "Reiniciando servicio SSH..."
    sudo systemctl restart sshd || sudo systemctl restart ssh
    
    log "SSH configurado correctamente"
}

# ------------------------------------------------------------
# Configurar autenticación SSH con GitHub y copia opcional a Windows
# ------------------------------------------------------------
setup_github_ssh() {
    log "Configurando autenticación SSH con GitHub..."

    SSH_DIR="$HOME/.ssh"
    SSH_KEY_PATH="$SSH_DIR/id_rsa"
    SSH_PUB_KEY_PATH="$SSH_KEY_PATH.pub"

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        info "Generando nueva clave SSH..."
        ssh-keygen -t rsa -b 4096 -C "houseunity@provision" -f "$SSH_KEY_PATH" -N ""
        log "Clave SSH generada en: $SSH_KEY_PATH"
    else
        info "Ya existe una clave SSH en $SSH_KEY_PATH, se reutilizará."
    fi

    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add "$SSH_KEY_PATH" >/dev/null 2>&1

    info "Clave pública generada:"
    echo "------------------------------------------------------------"
    cat "$SSH_PUB_KEY_PATH"
    echo "------------------------------------------------------------"
    info "Copia esta clave en tu cuenta de GitHub → Settings → SSH and GPG keys"

    read -r -p "¿Deseas probar la conexión con GitHub ahora? (s/n): " test_choice
    if [[ "$test_choice" =~ ^[sS]$ ]]; then
        ssh -T git@github.com || warn "No se pudo verificar la conexión con GitHub todavía."
    fi

    # --- NUEVO BLOQUE: Copiar clave pública automáticamente al host Windows ---
    read -r -p "¿Deseas copiar automáticamente la clave pública a tu máquina anfitriona Windows? (s/n): " copy_choice
    if [[ "$copy_choice" =~ ^[sS]$ ]]; then
        toggle_ssh_password_auth on

        read -r -p "Introduce la IP de tu máquina Windows (ej. 192.168.1.151): " WIN_IP
        read -r -p "Introduce tu usuario de Windows (ej. MIMI ESTUDIOS): " WIN_USER

        log "Intentando crear carpeta .ssh en Windows..."
        ssh -o StrictHostKeyChecking=no "$WIN_USER@$WIN_IP" 'powershell -Command "New-Item -ItemType Directory -Force -Path $env:USERPROFILE\.ssh"'

        log "Copiando clave pública a Windows..."
        scp -o StrictHostKeyChecking=no "$SSH_PUB_KEY_PATH" "$WIN_USER@$WIN_IP:/c/Users/$WIN_USER/.ssh/authorized_keys"

        log "Ajustando permisos en Windows..."
        ssh "$WIN_USER@$WIN_IP" 'powershell -Command "icacls $env:USERPROFILE\.ssh /grant $env:USERNAME:(OI)(CI)F; icacls $env:USERPROFILE\.ssh\authorized_keys /grant $env:USERNAME:F"'

        toggle_ssh_password_auth off
        log "Clave pública copiada correctamente y SSH asegurado nuevamente."
    else
        info "Omitido: no se copió la clave a Windows."
    fi
}

# Función para clonar el repositorio
clone_repository() {
    local repo_url=$1
    local target_dir=$2
    
    log "Clonando repositorio: $repo_url en $target_dir"
    
    if [ -d "$target_dir" ]; then
        warn "El directorio '$target_dir' ya existe. Intentando actualizar..."
        if [ ! -d "$target_dir/.git" ]; then
             error "El directorio existe pero no es un repositorio git. Borra '$target_dir' para continuar."
        fi
        
        sudo chown -R "$USER":"$USER" "$target_dir"
        cd "$target_dir"
        git pull origin main || git pull origin master 
    else
        log "Creando directorio y clonando repositorio..."
        sudo mkdir -p "$target_dir"
        sudo chown "$USER":"$USER" "$target_dir"
        git clone "$repo_url" "$target_dir"
        cd "$target_dir"
    fi
    
    log "Configurando permisos del repositorio..."
    find . -type d -exec chmod 755 {} \;
    find . -type f -exec chmod 644 {} \;
    
    log "Repositorio clonado/actualizado en: $target_dir"
}

# Función para validar estructura del proyecto HouseUnity
validate_project_structure() {
    log "Validando estructura del proyecto HouseUnity..."
    
    local required_files=(
        "docker-compose.yml"
        ".env.example" 
        "data/database/houseunity_bd.sql"
        "app/Models/Usuario.php"
        "app/Controllers"
        "app/View"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -e "$file" ]; then
            error "Archivo/directorio requerido no encontrado: $file"
        fi
    done
    
    log "Estructura del proyecto validada correctamente"
}

# Función para configurar el entorno del proyecto HouseUnity
setup_project() {
    local project_dir=$1
    
    log "Configurando proyecto HouseUnity para ambiente $ENV_MODE..."
    
    # 1. Validar estructura
    validate_project_structure
    
    # 2. Configurar archivo .env
    if [ ! -f .env ]; then
        info "Creando archivo .env a partir de .env.example"
        cp .env.example .env
        
        # Configurar valores según ambiente
        if [ "$ENV_MODE" == "prod" ]; then
            log "Configurando ambiente de PRODUCCIÓN..."
            # Generar passwords seguros
            DB_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
            ROOT_PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
            
            # Aplicar configuración de producción
            sed -i "s/tu_password_acá/$DB_PASS/g" .env
            sed -i "s/tu_root_password_acá/$ROOT_PASS/g" .env
            sed -i 's/APP_ENV=development/APP_ENV=production/g' .env
            sed -i 's/APP_DEBUG=true/APP_DEBUG=false/g' .env
            sed -i 's/SECURE_COOKIES=false/SECURE_COOKIES=true/g' .env
            sed -i 's|APP_URL=http://localhost:8080|APP_URL=https://tu-dominio.com|g' .env
            
            warn "IMPORTANTE: Revisa y actualiza las credenciales de email y dominio en .env"
            info "Password de BD generado: $DB_PASS"
            info "Password de Root generado: $ROOT_PASS"
        else
            log "Configurando ambiente de DESARROLLO..."
            # Solicitar passwords de desarrollo al usuario
            echo "Configura las contraseñas para la base de datos:"
            read -r -s -p "Password para base de datos: " DB_PASS
            echo
            DB_PASS=${DB_PASS:-houseunity123}

            read -r -s -p "Password para root de MySQL: " ROOT_PASS
            echo
            ROOT_PASS=${ROOT_PASS:-root123}
            
            # Aplicar passwords ingresadas
            sed -i "s/tu_password_acá/$DB_PASS/g" .env
            sed -i "s/tu_root_password_acá/$ROOT_PASS/g" .env
            
            info "Passwords configuradas para ambiente de desarrollo"
        fi
        
        log "Archivo .env configurado para ambiente: $ENV_MODE"
    else
        warn "El archivo .env ya existe. No se modificará."
        info "Si necesitas reconfigurarlo, elimina .env y ejecuta el script nuevamente."
    fi
    
    # 3. Crear directorios necesarios y configurar permisos para Docker
    log "Creando directorios necesarios..."
    mkdir -p public/uploads
    mkdir -p backup-system/logs
    
    log "Configurando permisos para contenedores Docker..."
    # Permisos 777 para que www-data/apache pueda escribir en Docker
    chmod -R 777 public/uploads
    chmod -R 755 backup-system/logs
    
    # Deshabilitar SELinux temporalmente si está activo (solo Rocky/CentOS)
    if command -v getenforce &> /dev/null; then
        if [ "$(getenforce)" != "Disabled" ]; then
            warn "SELinux detectado. Configurando contexto para Docker..."
            sudo setenforce 0 2>/dev/null || true
            # Hacer permanente (opcional)
            sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config 2>/dev/null || true
        fi
    fi
    
    # 4. Determinar comando Docker Compose
    DOCKER_COMPOSE_CMD="docker-compose"
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker"
        DOCKER_COMPOSE_SUBCMD="compose"
        info "Usando el plugin 'docker compose' (v2)."
    else
        DOCKER_COMPOSE_CMD="docker-compose"
        DOCKER_COMPOSE_SUBCMD=""
        info "Usando el binario 'docker-compose' (standalone)."
    fi

    # 5. Limpiar contenedores previos (si existen)
    log "Limpiando contenedores previos (si existen)..."
    if [ -n "$DOCKER_COMPOSE_SUBCMD" ]; then
        "$DOCKER_COMPOSE_CMD" "$DOCKER_COMPOSE_SUBCMD" down -v 2>/dev/null || true
    else
        "$DOCKER_COMPOSE_CMD" down -v 2>/dev/null || true
    fi
    
    # 6. Construir e iniciar contenedores
    log "Construyendo contenedores Docker..."
    if [ -n "$DOCKER_COMPOSE_SUBCMD" ]; then
        "$DOCKER_COMPOSE_CMD" "$DOCKER_COMPOSE_SUBCMD" build
    else
        "$DOCKER_COMPOSE_CMD" build
    fi
    
    log "Iniciando contenedores..."
    if [ -n "$DOCKER_COMPOSE_SUBCMD" ]; then
        "$DOCKER_COMPOSE_CMD" "$DOCKER_COMPOSE_SUBCMD" up --build -d
    else
        "$DOCKER_COMPOSE_CMD" up --build -d
    fi
    
    # 7. Esperar que MySQL esté listo
    log "Esperando que MySQL esté listo..."
    sleep 10
    
    # 8. Configurar permisos finales para uploads (crucial para Docker)
    log "Configurando permisos finales para uploads..."
    if [ -d "$project_dir/public/uploads" ]; then
        # 777 permite que el usuario del contenedor (www-data) pueda escribir
        sudo chmod -R 777 "$project_dir/public/uploads"
        info "Directorio public/uploads configurado con permisos 777"
    fi
    
    log "Proyecto HouseUnity configurado correctamente"
}

# Función para mostrar información de acceso
show_access_info() {
    log "════════════════════════════════════════════════════════════════════"
    log "✓ Instalación completada exitosamente"
    log ""
    
    # Detectar IP de la VM
    VM_IP=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
    
    # Detectar puertos del docker-compose.yml
    BACKEND_PORT=$(grep -A 5 "ports:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | grep -oP '"\K\d+(?=:)' | head -1)
    FRONTEND_PORT=$(grep -A 5 "ports:" "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | grep -oP '"\K\d+(?=:)' | sed -n '2p')
    
    # Valores por defecto si no se encuentran
    BACKEND_PORT=${BACKEND_PORT:-8080}
    FRONTEND_PORT=${FRONTEND_PORT:-5173}
    
    log "📍 Accede a tu aplicación desde tu navegador (Windows/otro PC):"
    log ""
    
    # Detectar si es NAT o Bridge
    if [[ "$VM_IP" == 10.0.2.* ]]; then
        warn "⚠️  Red en modo NAT detectada"
        log "   Configura Port Forwarding en VirtualBox:"
        log ""
        log "   VirtualBox → Settings → Network → Port Forwarding"
        log "   • Host Port: $BACKEND_PORT  → Guest Port: $BACKEND_PORT"
        log "   • Host Port: $FRONTEND_PORT → Guest Port: $FRONTEND_PORT"
        log ""
        log "   Luego accede con:"
        log "   • Aplicación:  http://localhost:$BACKEND_PORT"
        log "   • Frontend:    http://localhost:$FRONTEND_PORT"
    else
        log "   • Aplicación Web:  http://$VM_IP:$BACKEND_PORT"
        log "   • Frontend Dev:    http://$VM_IP:$FRONTEND_PORT"
        log "   • Base de Datos:   mysql://$VM_IP:3307"
    fi
    
    log ""
    log "📊 Comandos útiles desde SSH:"
    log "   • Ver logs:       docker compose logs -f"
    log "   • Ver estado:     docker compose ps"
    log "   • Reiniciar:      docker compose restart"
    log "   • Detener:        docker compose down"
    log "   • Reconstruir:    docker compose up --build -d"
    log ""
    log "🔍 Probar desde Rocky Linux:"
    log "   • curl http://localhost:$BACKEND_PORT"
    log "   • docker ps"
    log "   • ss -tulpn | grep -E '$BACKEND_PORT|$FRONTEND_PORT'"
    log ""
    log "════════════════════════════════════════════════════════════════════"
}

# Función principal
main() {
    log "Iniciando provisionamiento de HouseUnity"
    
    check_sudo
    detect_os
    info "Sistema operativo detectado: $OS $OS_VERSION"
    
    load_or_prompt_config
    
    # Provisionamiento base
    update_system
    install_basic_tools
    install_docker
    install_docker_compose
    setup_ssh
    setup_github_ssh
    
    # Configuración del proyecto
    clone_repository "$REPO_URL" "$PROJECT_DIR"
    setup_project "$PROJECT_DIR"
    
    # Mostrar información de acceso
    show_access_info
    
    # Advertencias finales
    warn "⚠️  Recuerda cerrar sesión y volver a iniciar para que los cambios del grupo 'docker' surtan efecto."
    
    if [ "$ENV_MODE" == "prod" ]; then
        warn "⚠️  PRODUCCIÓN: Revisa y actualiza las credenciales en .env antes de usar en producción."
    fi
}

# Ejecutar función principal
main "$@"