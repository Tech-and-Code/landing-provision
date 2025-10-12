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
    log "Actualizando el sistema..."
    case "$OS" in
        ubuntu|debian)
            sudo apt-get update -qq
            sudo apt-get upgrade -y -qq
            ;;
        centos|rhel|fedora|rocky)
            sudo yum update -y -q
            ;;
        *)
            error "Sistema operativo no soportado: $OS"
            ;;
    esac
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
            sudo yum install -y -q git curl wget rsync openssh-clients openssh-server \
                unzip nano htop vim make tree net-tools
            ;;
        *)
            error "Sistema operativo no soportado para la instalación de herramientas básicas: $OS"
            ;;
    esac
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
                sudo dnf -y -q install dnf-plugins-core
                sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                sudo dnf -y -q install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            else
                sudo yum install -y -q yum-utils
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                sudo yum install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
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

# Función para configurar el acceso SSH a GitHub
setup_github_ssh() {
    log "Configurando acceso SSH a GitHub..."
    
    local SSH_KEY_PATH="$HOME/.ssh/id_rsa"
    local SSH_PUB_KEY_PATH="$HOME/.ssh/id_rsa.pub"

    if [ -f "$SSH_KEY_PATH" ]; then
        warn "La clave SSH ya existe. No se generará una nueva."
    else
        info "Generando nueva clave SSH..."
        ssh-keygen -t rsa -b 4096 -C "houseunity@provision-script" -N "" -f "$SSH_KEY_PATH"
        log "Clave SSH generada."
    fi
    
    log "Agrega la siguiente clave pública a tu cuenta de GitHub:"
    echo -e "${YELLOW}"
    cat "$SSH_PUB_KEY_PATH"
    echo -e "${NC}"
    
    read -r -p "Presiona Enter después de haber agregado la clave a GitHub..."
    
    log "Probando conexión SSH con GitHub..."
    ssh -T git@github.com || true
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
    
    # 3. Crear directorios necesarios
    log "Creando directorios necesarios..."
    mkdir -p public/uploads
    mkdir -p backup-system/logs
    chmod 755 public/uploads
    chmod 755 backup-system/logs
    
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

    # 5. Construir e iniciar contenedores
    log "Construyendo contenedores Docker..."
    if [ -n "$DOCKER_COMPOSE_SUBCMD" ]; then
        "$DOCKER_COMPOSE_CMD" "$DOCKER_COMPOSE_SUBCMD" build
    else
        "$DOCKER_COMPOSE_CMD" build
    fi
    
    log "Iniciando contenedores..."
    if [ -n "$DOCKER_COMPOSE_SUBCMD" ]; then
        "$DOCKER_COMPOSE_CMD" "$DOCKER_COMPOSE_SUBCMD" up -d
    else
        "$DOCKER_COMPOSE_CMD" up -d
    fi
    
    # 6. Esperar que MySQL esté listo
    log "Esperando que MySQL esté listo..."
    sleep 10
    
    # 7. Configurar permisos finales
    log "Configurando permisos finales..."
    if [ -d "$project_dir/public/uploads" ]; then
        sudo chmod -R 775 "$project_dir/public/uploads"
        sudo chown -R "$USER:$USER" "$project_dir/public/uploads"
    fi
    
    log "Proyecto HouseUnity configurado correctamente"
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
    
    # Información final
    log "¡Provisionamiento de HouseUnity completado exitosamente!"
    info "Ambiente: $ENV_MODE"
    info "Directorio: $PROJECT_DIR"
    info "Aplicación web: http://localhost:8080"
    info "Base de datos MySQL: localhost:3307"
    info "Sistema de backup: Configurado automáticamente"
    
    DOCKER_COMPOSE_CMD="docker-compose"
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    fi
    
    log "Comandos útiles:"
    info "Ver logs: $DOCKER_COMPOSE_CMD logs -f"
    info "Detener: $DOCKER_COMPOSE_CMD down"
    info "Iniciar: $DOCKER_COMPOSE_CMD up -d"
    info "Estado: $DOCKER_COMPOSE_CMD ps"
    
    warn "Recuerda cerrar sesión y volver a iniciar para que los cambios del grupo 'docker' surtan efecto."
    
    if [ "$ENV_MODE" == "prod" ]; then
        warn "PRODUCCIÓN: Revisa y actualiza las credenciales en .env antes de usar en producción."
    fi
}

# Ejecutar función principal
main "$@"