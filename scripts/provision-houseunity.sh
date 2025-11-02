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
    
    # Detectar el usuario y su home
    local EFFECTIVE_USER="${SUDO_USER:-$USER}"
    local USER_HOME
    USER_HOME="$(getent passwd "$EFFECTIVE_USER" | cut -d: -f6)"
    DEFAULT_DIR="$USER_HOME/$REPO_NAME"

    # 3. Definir el directorio de instalación (siempre preguntar)
    unset PROJECT_DIR

    while [ -z "$PROJECT_DIR" ]; do
    read -r -p "Introduce el directorio de instalación: [$DEFAULT_DIR] " input_dir
    PROJECT_DIR=${input_dir:-$DEFAULT_DIR}

    # Detectar si el destino es el HOME del usuario
    local EFFECTIVE_USER="${SUDO_USER:-$USER}"
    local USER_HOME
    USER_HOME="$(getent passwd "$EFFECTIVE_USER" | cut -d: -f6)"

    if [ "$PROJECT_DIR" = "$USER_HOME" ]; then
        warn "El destino es el directorio HOME del usuario. Creando subcarpeta '$REPO_NAME'..."
        PROJECT_DIR="$USER_HOME/$REPO_NAME"
    fi

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

    # Detectar el usuario real (el que ejecutó sudo)
    local EFFECTIVE_USER="${SUDO_USER:-$USER}"
    
    if [ -n "$EFFECTIVE_USER" ] && [ "$EFFECTIVE_USER" != "root" ]; then
        if ! id -nG "$EFFECTIVE_USER" | grep -qw "docker"; then
            log "Agregando usuario '$EFFECTIVE_USER' al grupo 'docker'..."
            sudo usermod -aG docker "$EFFECTIVE_USER"
            log "✓ Usuario '$EFFECTIVE_USER' agregado al grupo docker"
        else
            log "Usuario '$EFFECTIVE_USER' ya está en el grupo docker"
        fi
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

# Función para configurar sistema de respaldo completo
setup_backup_system() {
    log "Configurando sistema de respaldo (NFS y rsync)..."
    
    # 1. Instalar paquetes
    case "$OS" in
        ubuntu|debian)
            sudo apt-get install -y -qq nfs-kernel-server nfs-common rsync
            ;;
        centos|rhel|fedora|rocky)
            sudo dnf install -y nfs-utils rsync
            ;;
        *)
            warn "Sistema operativo no reconocido para instalar NFS. Saltando..."
            return
            ;;
    esac
    
    # 2. Crear directorio /export
    log "Creando directorio /export..."
    sudo mkdir -p /export
    sudo chmod 777 /export
    sudo chown nobody:nogroup /export 2>/dev/null || sudo chown nobody:nobody /export 2>/dev/null || true
    
    # 3. Configurar NFS exports
    log "Configurando NFS exports..."
    local NFS_EXPORTS="/etc/exports"
    
    # Hacer backup del archivo original si existe
    if [ -f "$NFS_EXPORTS" ]; then
        sudo cp "$NFS_EXPORTS" "${NFS_EXPORTS}.bak" 2>/dev/null || true
    fi
    
    # Eliminar entradas previas de /export si existen
    sudo sed -i '/\/export/d' "$NFS_EXPORTS" 2>/dev/null || true
    
    # Agregar nueva entrada con formato correcto
    echo "/export *(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a "$NFS_EXPORTS" > /dev/null
    log "✓ /export configurado en $NFS_EXPORTS"
    
    # Aplicar configuración con manejo de errores
    if sudo exportfs -ra 2>/dev/null; then
        log "✓ NFS exports aplicados correctamente"
    else
        warn "Hubo un problema al aplicar NFS exports. Verificando..."
        # Mostrar contenido del archivo para debug
        sudo cat "$NFS_EXPORTS"
        # Intentar aplicar solo /export específicamente
        sudo exportfs -o rw,sync,no_subtree_check,no_root_squash *:/export 2>/dev/null || true
    fi
    
    # 4. Habilitar e iniciar NFS
    case "$OS" in
        ubuntu|debian)
            sudo systemctl enable nfs-kernel-server 2>/dev/null || true
            sudo systemctl restart nfs-kernel-server
            ;;
        centos|rhel|fedora|rocky)
            sudo systemctl enable nfs-server 2>/dev/null || true
            sudo systemctl restart nfs-server
            ;;
    esac
    
    # 5. Copiar archivos de configuración rsync desde el repo
    log "Configurando rsync daemon desde archivos del repositorio..."
    local PROJECT_DIR_FOR_BACKUP="$1"
    
    if [ -f "$PROJECT_DIR_FOR_BACKUP/docker/scripts/rsyncd.conf" ]; then
        sudo cp "$PROJECT_DIR_FOR_BACKUP/docker/scripts/rsyncd.conf" /etc/rsyncd.conf
        log "✓ rsyncd.conf copiado desde el repositorio"
    else
        warn "No se encontró rsyncd.conf en el repo. Saltando configuración rsync."
        return
    fi
    
    if [ -f "$PROJECT_DIR_FOR_BACKUP/docker/scripts/rsyncd.secrets" ]; then
        sudo cp "$PROJECT_DIR_FOR_BACKUP/docker/scripts/rsyncd.secrets" /etc/rsyncd.secrets
        sudo chmod 600 /etc/rsyncd.secrets
        log "✓ rsyncd.secrets copiado desde el repositorio"
        
        # Mostrar contraseña
        BACKUP_PASSWORD=$(grep "backupuser:" /etc/rsyncd.secrets | cut -d: -f2)
        info "Usuario rsync: backupuser"
        info "Contraseña rsync: $BACKUP_PASSWORD"
    else
        warn "No se encontró rsyncd.secrets en el repo. Saltando configuración rsync."
        return
    fi
    
    # 6. Iniciar rsync daemon
    if [[ "$OS" =~ ^(centos|rhel|fedora|rocky)$ ]]; then
        sudo systemctl enable rsyncd 2>/dev/null || true
        sudo systemctl restart rsyncd 2>/dev/null || sudo rsync --daemon
    else
        sudo pkill rsync 2>/dev/null || true
        sudo rsync --daemon
    fi
    
    # 7. Configurar firewall
    log "Configurando firewall..."
    if command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --permanent --add-service=nfs 2>/dev/null || true
        sudo firewall-cmd --permanent --add-port=873/tcp 2>/dev/null || true
        sudo firewall-cmd --permanent --add-port=8873/tcp 2>/dev/null || true
        sudo firewall-cmd --reload 2>/dev/null || true
    elif command -v ufw &> /dev/null; then
        sudo ufw allow 873/tcp 2>/dev/null || true
        sudo ufw allow 8873/tcp 2>/dev/null || true
        sudo ufw allow nfs 2>/dev/null || true
    fi
    
    log "✓ Sistema de respaldo configurado correctamente"
}

# Función auxiliar para activar/desactivar autenticación por contraseña en SSH temporalmente
toggle_ssh_password_auth() {
    local action=$1
    local ssh_config="/etc/ssh/sshd_config"

    if [[ "$action" == "enable" ]]; then
        echo "🔓 Habilitando temporalmente autenticación por contraseña..."
        sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$ssh_config"
    elif [[ "$action" == "disable" ]]; then
        echo "🔒 Deshabilitando autenticación por contraseña..."
        sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$ssh_config"
    else
        echo "Uso: toggle_ssh_password_auth <enable|disable>"
        return 1
    fi

    sudo systemctl restart sshd || sudo systemctl restart ssh
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
    log "Configurando acceso SSH a GitHub..."

    # Detectar el usuario real incluso si se ejecuta con sudo
    local EFFECTIVE_USER="${SUDO_USER:-$USER}"
    local USER_HOME
    USER_HOME="$(getent passwd "$EFFECTIVE_USER" | cut -d: -f6)"

    local SSH_KEY_PATH="$USER_HOME/.ssh/id_rsa"
    local SSH_PUB_KEY_PATH="$USER_HOME/.ssh/id_rsa.pub"

    mkdir -p "$USER_HOME/.ssh"
    chown "$EFFECTIVE_USER":"$EFFECTIVE_USER" "$USER_HOME/.ssh"
    chmod 700 "$USER_HOME/.ssh"

    if [ -f "$SSH_KEY_PATH" ]; then
        log "Clave SSH existente detectada. Omitiendo generación."
    else
        info "Generando nueva clave SSH..."
        sudo -u "$EFFECTIVE_USER" ssh-keygen -t rsa -b 4096 -C "houseunity@provision-script" -N "" -f "$SSH_KEY_PATH"
        log "Clave SSH generada correctamente."
    fi

    echo
    log "Tu clave pública es:"
    echo -e "${YELLOW}"
    sudo -u "$EFFECTIVE_USER" cat "$SSH_PUB_KEY_PATH"
    echo -e "${NC}"
    echo ""
    
    # Detectar la IP de la VM
    VM_IP=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
    
    info "📋 Para copiar la clave SSH desde Windows:"
    echo ""
    echo "   Habilitar SSH con contraseña temporalmente (ejecuta en la VM):"
    echo -e "${YELLOW}   sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config${NC}"
    echo -e "${YELLOW}   sudo systemctl restart sshd${NC}"
    echo ""
    echo "   Desde Windows (Git Bash), ejecuta:"
    echo -e "${YELLOW}   scp $EFFECTIVE_USER@$VM_IP:~/.ssh/id_rsa.pub ~/.ssh/houseunity_vm.pub${NC}"
    echo -e "${YELLOW}   cat ~/.ssh/houseunity_vm.pub${NC}"
    echo ""
    echo "   Después de copiar, deshabilitar password SSH (ejecuta en la VM):"
    echo -e "${YELLOW}   sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config${NC}"
    echo -e "${YELLOW}   sudo systemctl restart sshd${NC}"
    echo ""
    
    read -r -p "¿Quieres que el script habilite password SSH temporalmente para que copies la clave? (s/n): " enable_pwd
    if [[ "$enable_pwd" =~ ^[sS]$ ]]; then
        log "Habilitando autenticación por contraseña temporalmente..."
        sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
        sudo systemctl restart sshd
        
        echo ""
        warn "⚠️  Autenticación por contraseña HABILITADA temporalmente"
        echo ""
        echo "Desde Windows (Git Bash), ejecuta:"
        echo -e "${YELLOW}   scp $EFFECTIVE_USER@$VM_IP:~/.ssh/id_rsa.pub ~/.ssh/houseunity_vm.pub${NC}"
        echo -e "${YELLOW}   cat ~/.ssh/houseunity_vm.pub${NC}"
        echo ""
        echo "Copia la clave y agrégala a GitHub (Settings → SSH and GPG keys → New SSH key)"
        echo ""
        read -r -p "Presiona Enter cuando hayas copiado la clave y la hayas agregado a GitHub..."
        
        log "Deshabilitando autenticación por contraseña..."
        sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        sudo systemctl restart sshd
        log "✓ Autenticación por contraseña deshabilitada"
    else
        echo ""
        log "Agrega la clave pública a tu cuenta de GitHub (Settings → SSH and GPG keys → New SSH key)"
        echo "Puedes copiar la clave desde arriba (la línea amarilla que empieza con ssh-rsa)"
        read -r -p "Presiona Enter cuando la hayas agregado..."
    fi

    log "Probando conexión SSH con GitHub..."
    sudo -u "$EFFECTIVE_USER" ssh -T git@github.com || true
}

clone_repository() {
    local repo_url=$1
    local target_dir=$2

    # Detectar el usuario real incluso si se ejecuta con sudo
    local EFFECTIVE_USER="${SUDO_USER:-$USER}"

    log "Clonando repositorio: $repo_url en $target_dir"

    if [ -d "$target_dir" ]; then
        # El directorio existe, verificar si está vacío
        if [ -z "$(ls -A "$target_dir" 2>/dev/null)" ]; then
            # Directorio vacío, clonar directamente
            log "Directorio existe pero está vacío. Clonando repositorio..."
            if sudo -u "$EFFECTIVE_USER" git clone "$repo_url" "$target_dir"; then
                cd "$target_dir"
            else
                error "Fallo al clonar el repositorio. Verifica la URL y los permisos SSH."
                return 1
            fi
        elif [ -d "$target_dir/.git" ]; then
            # Es un repositorio git existente, actualizar
            warn "El directorio '$target_dir' ya contiene un repositorio git. Actualizando..."
            
            sudo chown -R "$EFFECTIVE_USER":"$EFFECTIVE_USER" "$target_dir"
            
            if ! cd "$target_dir"; then
                error "No se puede acceder al directorio '$target_dir'"
                return 1
            fi

            # Detectar rama principal automáticamente
            local default_branch
            if ! default_branch=$(sudo -u "$EFFECTIVE_USER" git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}'); then
                warn "No se pudo detectar la rama principal. Usando 'main'..."
                default_branch="main"
            fi
            log "Rama principal: $default_branch"

            # Intentar actualizar el repositorio
            log "Actualizando repositorio desde origin/$default_branch..."
            if sudo -u "$EFFECTIVE_USER" git pull origin "$default_branch"; then
                log "✓ Repositorio actualizado correctamente"
            else
                error "Fallo al actualizar el repositorio. Verifica conflictos o problemas de conexión."
                return 1
            fi
        else
            # Directorio tiene archivos pero no es un repo git
            warn "El directorio '$target_dir' existe y contiene archivos pero NO es un repositorio git."
            echo ""
            echo "Contenido actual del directorio:"
            ls -la "$target_dir" | head -10
            echo ""
            echo "Opciones:"
            echo "1. Borrar todo y clonar el repositorio (CUIDADO: borrará archivos)"
            echo "2. Clonar en un subdirectorio temporal y mover después"
            echo "3. Cancelar y resolver manualmente"
            echo ""
            read -r -p "¿Qué deseas hacer? (1/2/3): " choice
            
            case $choice in
                1)
                    warn "Borrando contenido de $target_dir..."
                    sudo rm -rf "$target_dir"/*
                    sudo rm -rf "$target_dir"/.[!.]*
                    log "Clonando repositorio en directorio limpio..."
                    if sudo -u "$EFFECTIVE_USER" git clone "$repo_url" "$target_dir"; then
                        cd "$target_dir"
                    else
                        error "Fallo al clonar el repositorio."
                        return 1
                    fi
                    ;;
                2)
                    local temp_dir="${target_dir}_temp_clone"
                    log "Clonando en directorio temporal: $temp_dir"
                    if sudo -u "$EFFECTIVE_USER" git clone "$repo_url" "$temp_dir"; then
                        warn "Repositorio clonado en: $temp_dir"
                        warn "Revisa manualmente y mueve los archivos necesarios a: $target_dir"
                        cd "$temp_dir"
                    else
                        error "Fallo al clonar el repositorio."
                        return 1
                    fi
                    ;;
                3)
                    error "Operación cancelada. Limpia el directorio '$target_dir' manualmente y vuelve a ejecutar."
                    return 1
                    ;;
                *)
                    error "Opción inválida. Operación cancelada."
                    return 1
                    ;;
            esac
        fi
    else
        # El directorio no existe, crear y clonar
        log "Creando directorio y clonando repositorio..."
        if sudo -u "$EFFECTIVE_USER" git clone "$repo_url" "$target_dir"; then
            cd "$target_dir"
        else
            error "Fallo al clonar el repositorio. Verifica la URL y los permisos SSH."
            return 1
        fi
    fi

    log "Configurando permisos del repositorio..."
    sudo chown -R "$EFFECTIVE_USER":"$EFFECTIVE_USER" "$target_dir"
    find "$target_dir" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$target_dir" -type f -exec chmod 644 {} \; 2>/dev/null || true

    log "✓ Repositorio listo en: $target_dir"
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
            
            warn "IMPORTANTE: Revisar y actualizar las credenciales de email y dominio en .env"
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
    
    # 7. Esperar que MySQL esté completamente listo
    log "Esperando que MySQL complete la inicialización (esto puede tomar 1-2 minutos)..."
    
    # Esperar a que los contenedores estén "Up"
    info "Verificando que los contenedores estén corriendo..."
    sleep 10
    
    # Esperar específicamente a que MySQL Master termine de inicializar
    info "Esperando que MySQL Master complete los scripts de inicialización..."
    local mysql_ready=false
    local max_wait=120  # 2 minutos máximo
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        # Verificar si MySQL acepta conexiones y si terminó de ejecutar scripts de init
        if docker exec houseunity-mysql-master mysqladmin -h 127.0.0.1 --protocol=TCP ping --silent 2>/dev/null; then
            # MySQL responde, verificar si terminó la inicialización viendo los logs
            local last_log=$(docker logs houseunity-mysql-master --tail 5 2>/dev/null)
            
            # Buscar indicadores de que terminó la inicialización
            if echo "$last_log" | grep -q "ready for connections" && \
               ! echo "$last_log" | grep -q "Entrypoint"; then
                mysql_ready=true
                break
            fi
        fi
        
        echo -n "."
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    echo ""
    
    if [ "$mysql_ready" = true ]; then
        log "✓ MySQL Master está completamente listo"
    else
        warn "MySQL Master puede no estar completamente listo. Esperando 20 segundos adicionales..."
        sleep 20
    fi
    
    # Hacer lo mismo para MySQL Slave
    info "Esperando que MySQL Slave complete la inicialización..."
    mysql_ready=false
    elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        if docker exec houseunity-mysql-slave mysqladmin -h 127.0.0.1 --protocol=TCP ping --silent 2>/dev/null; then
            local last_log=$(docker logs houseunity-mysql-slave --tail 5 2>/dev/null)
            if echo "$last_log" | grep -q "ready for connections" && \
               ! echo "$last_log" | grep -q "Entrypoint"; then
                mysql_ready=true
                break
            fi
        fi
        echo -n "."
        sleep 3
        elapsed=$((elapsed + 3))
    done
    
    echo ""
    
    if [ "$mysql_ready" = true ]; then
        log "✓ MySQL Slave está completamente listo"
    else
        warn "MySQL Slave puede no estar completamente listo. Continuando de todas formas..."
    fi
    
    # 8. Configurar permisos finales para uploads (crucial para Docker)
    log "Configurando permisos finales para uploads..."
    if [ -d "$project_dir/public/uploads" ]; then
        # 777 permite que el usuario del contenedor (www-data) pueda escribir
        sudo chmod -R 777 "$project_dir/public/uploads"
        info "Directorio public/uploads configurado con permisos 777"
    fi
    
    log "Proyecto HouseUnity configurado correctamente"
}

# Función para configurar replicación MySQL Master-Slave
setup_mysql_replication() {
    log " Configurando replicación MySQL Master-Slave..."
    
    # Verificar que los contenedores estén corriendo
    if ! docker ps | grep -q "houseunity-mysql-master"; then
        warn "Contenedor MySQL Master no encontrado. La replicación no se configurará."
        return 1
    fi
    
    if ! docker ps | grep -q "houseunity-mysql-slave"; then
        warn "Contenedor MySQL Slave no encontrado. La replicación no se configurará."
        return 1
    fi
    
    # Cargar variables de entorno desde .env
    if [ -f .env ]; then
        log "Cargando variables desde .env..."
        set -a  # Marcar todas las variables para export
        source <(grep -E '^[A-Z_]+=.*' .env | grep -v '^#')
        set +a  # Desactivar auto-export
        
        # Verificar que se cargó la contraseña
        if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
            error "MYSQL_ROOT_PASSWORD no está definida en .env"
        fi
        info "Usando MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD:0:3}*** (primeros 3 caracteres)"
    else
       error "Archivo .env no encontrado en el directorio actual: $(pwd)"
    fi
    
    # Esperar a que MySQL Master esté listo (ya deberíahaberse hecho antes, pero verificamos)
    info "Verificando conexión a MySQL Master..."
    
    # Cargar variables de entorno desde .env
    if [ -f .env ]; then
        set -a  # Marcar todas las variables para export
        source <(grep -E '^[A-Z_]+=.*' .env | grep -v '^#')
        set +a  # Desactivar auto-export
        
        if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
            warn "MYSQL_ROOT_PASSWORD no está definida en .env"
            return 1
        fi
    else
       warn "Archivo .env no encontrado"
       return 1
    fi
    
    # Verificar conexión con reintentos simples
    local attempt=0
    local max_attempts=10
    
    info "Probando conexión a MySQL Master..."
    while [ $attempt -lt $max_attempts ]; do
        if docker exec houseunity-mysql-master mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
            log "✓ Conexión a MySQL Master exitosa"
            break
        fi
        
        attempt=$((attempt + 1))
        if [ $attempt -lt $max_attempts ]; then
            echo -n "."
            sleep 3
        else
            echo ""
            warn "No se pudo conectar a MySQL Master después de $max_attempts intentos"
            echo "Últimas líneas del log:"
            docker logs houseunity-mysql-master --tail 20
            warn "Saltando configuración de replicación"
            return 1
        fi
    done
    echo ""
    
    # Crear usuario de replicación en el Master
    info "Configurando usuario de replicación en Master..."
    
    # Primero, eliminar el usuario si ya existe (para evitar conflictos)
    info "Eliminando usuario de replicación anterior (si existe)..."
    docker exec houseunity-mysql-master mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e \
        "DROP USER IF EXISTS 'repl_user'@'%';" > /dev/null 2>&1 || true
    
    # Crear el usuario de nuevo
    info "Creando usuario de replicación..."
    if docker exec houseunity-mysql-master mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e \
        "CREATE USER 'repl_user'@'%' IDENTIFIED WITH mysql_native_password BY 'Repl1c@2024';" 2>&1; then
        log "✓ Usuario de replicación creado"
    else
        warn "Error al crear usuario de replicación"
        echo "Intentando verificar si el usuario existe:"
        docker exec houseunity-mysql-master mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e \
            "SELECT user, host FROM mysql.user WHERE user='repl_user';" 2>&1
        warn "Saltando configuración de replicación"
        return 1
    fi
    
    # Otorgar permisos
    info "Otorgando permisos de replicación..."
    if docker exec houseunity-mysql-master mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e \
        "GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';" 2>&1; then
        log "✓ Permisos de replicación otorgados"
    else
        warn "Error al otorgar permisos de replicación. Saltando configuración."
        return 1
    fi
    
    # Aplicar cambios
    docker exec houseunity-mysql-master mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;" > /dev/null 2>&1
    log "✅ Usuario de replicación configurado correctamente"
    
    # Obtener el estado del Master
    info "Obteniendo estado del Master..."
    MASTER_STATUS=$(docker exec houseunity-mysql-master mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW MASTER STATUS\G")
    MASTER_LOG_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
    MASTER_LOG_POS=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')
    
    if [ -z "$MASTER_LOG_FILE" ] || [ -z "$MASTER_LOG_POS" ]; then
        warn "No se pudo obtener el estado del Master. Saltando replicación."
        return 1
    fi
    
    info "Master Log File: $MASTER_LOG_FILE"
    info "Master Log Position: $MASTER_LOG_POS"
    
    # Configurar el Slave
    info "Configurando Slave para conectarse al Master..."
    docker exec houseunity-mysql-slave mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e "
    STOP SLAVE;
    CHANGE MASTER TO 
        MASTER_HOST='mysql',
        MASTER_USER='repl_user',
        MASTER_PASSWORD='Repl1c@2024',
        MASTER_LOG_FILE='$MASTER_LOG_FILE',
        MASTER_LOG_POS=$MASTER_LOG_POS;
    START SLAVE;
    "
    
    if [ $? -eq 0 ]; then
        log "✅ Slave configurado correctamente"
    else
        warn "Error al configurar Slave. Saltando replicación."
        return 1
    fi
    
    # Verificar el estado de la replicación
    sleep 3
    info "Verificando estado de la replicación..."
    SLAVE_STATUS=$(docker exec houseunity-mysql-slave mysql -h 127.0.0.1 --protocol=TCP -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW SLAVE STATUS\G" 2>/dev/null)
    
    IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}')
    SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')
    SECONDS_BEHIND=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master:" | awk '{print $2}')
    
    log ""
    log "Estado de la Replicación:"
    log "   • Slave_IO_Running: $IO_RUNNING"
    log "   • Slave_SQL_Running: $SQL_RUNNING"
    log "   • Seconds_Behind_Master: $SECONDS_BEHIND"
    log ""
    
    if [ "$IO_RUNNING" == "Yes" ] && [ "$SQL_RUNNING" == "Yes" ]; then
        log "✅ ¡Replicación MySQL Master-Slave configurada exitosamente!"
        log ""
        log " Información de la replicación:"
        log "   • Master: localhost:3307 (houseunity-mysql-master)"
        log "   • Slave:  localhost:3308 (houseunity-mysql-slave)"
        log "   • Base de datos: ${DB_NAME}"
        log ""
        return 0
    else
        warn "⚠️ La replicación no está funcionando correctamente"
        warn "Revisa los logs con: docker logs houseunity-mysql-slave"
        return 1
    fi
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
    
    log " Accede a tu aplicación desde tu navegador (Windows/otro PC):"
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
    log " Comandos útiles desde SSH:"
    log "   • Ver logs:       docker compose logs -f"
    log "   • Ver estado:     docker compose ps"
    log "   • Reiniciar:      docker compose restart"
    log "   • Detener:        docker compose down"
    log "   • Reconstruir:    docker compose up --build -d"
    log ""
    log " Sistema de Respaldo:"
    log "   • Directorio:     /export"
    log "   • Puerto rsync HOST:      873"
    log "   • Puerto rsync Docker:    8873"
    log "   • Usuario:        backupuser"
    log "   • Contraseña:     Ver /etc/rsyncd.secrets (sudo cat /etc/rsyncd.secrets)"
    log ""
    log "   Ejemplo desde cliente (rsync del HOST):"
    log "   echo 'CONTRASEÑA' > rsync.pass && chmod 600 rsync.pass"
    log "   rsync -av --port=873 --password-file=rsync.pass archivo.txt backupuser@$VM_IP::backups"
    log ""
    log " Replicación MySQL Master-Slave:"
    log "   • Master (R/W):   mysql://$VM_IP:3307"
    log "   • Slave (R):      mysql://$VM_IP:3308"
    log ""
    log "   Verificar estado:"
    log "   cd ~/Tech-Code-Proyecto/docker/scripts"
    log "   ./check-replication.sh"
    log ""
    log " Probar desde Rocky Linux:"
    log "   • curl http://localhost:$BACKEND_PORT"
    log "   • docker ps"
    log "   • ss -tulpn | grep -E '$BACKEND_PORT|$FRONTEND_PORT|873|8873|3307|3308'"
    log "   • ls -lh /export"
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
    
    # Configurar sistema de respaldo (después de clonar repo)
    setup_backup_system "$PROJECT_DIR"
    
    setup_project "$PROJECT_DIR"
    
    # Configurar replicación MySQL Master-Slave (después de levantar contenedores)
    setup_mysql_replication || warn "La replicación MySQL no se configuró. Puedes configurarla manualmente más tarde."
    
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