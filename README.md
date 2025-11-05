# landing-provision

Página web estática para alojar el script provision.sh, para luego poder descargarlo y ejecutarlo remotamente.

## 📁 Estructura del Proyecto

```
landing-provision/
├── index.html              # Landing page para descargar el script
├── main.js                 # JavaScript de la landing
├── scripts/
│   ├── provision-houseunity.sh  # Script principal de provisión
│   └── show-info.sh             # Script para mostrar info de acceso
├── ACCESO.md               # Guía rápida de acceso
└── README.md               # Este archivo
```

## 🚀 Uso del Script de Provisión

### Descarga y Ejecución

```bash
# Descargar desde la landing page
curl -O https://tu-dominio.com/scripts/provision-houseunity.sh

# O descargar directamente desde GitHub
curl -O https://raw.githubusercontent.com/Tech-and-Code/landing-provision/main/scripts/provision-houseunity.sh

# Dar permisos de ejecución
chmod +x provision-houseunity.sh

# Ejecutar
sudo bash provision-houseunity.sh
```

## 📱 Información de Acceso a tu Aplicación

Después de ejecutar el script de provisión, puedes ver toda la información de acceso ejecutando:

```bash
bash scripts/show-info.sh
```

O consulta la guía completa: [ACCESO.md](ACCESO.md)

### Lo que incluye el script de información:

- 🌐 URLs de acceso (Backend, Frontend, MySQL)
- 🐳 Comandos Docker útiles
- 🗄️ Conexión a bases de datos
- 🔄 Estado de replicación MySQL
- 💾 Configuración de backups (rsync)
- 🔍 Comandos de debugging
- 🆘 Solución de problemas comunes

## 🎯 Características del Script de Provisión

El script `provision-houseunity.sh` configura automáticamente:

- ✅ Actualización del sistema (Ubuntu/Debian o Rocky Linux/CentOS)
- ✅ Instalación de Docker y Docker Compose
- ✅ Configuración de SSH (con soporte para puerto 22 y 443)
- ✅ Detección automática de puerto bloqueado y conversión a HTTPS
- ✅ Clonación del repositorio de tu proyecto
- ✅ Configuración de MySQL Master-Slave Replication
- ✅ Sistema de respaldos con rsync
- ✅ Configuración de firewall automática
- ✅ Levantamiento de servicios con Docker Compose

## 🔐 SSH sobre Puerto 443

Si el puerto 22 está bloqueado por tu institución, el script:

1. **Detecta automáticamente** que el puerto 22 no está disponible
2. **Configura SSH sobre HTTPS** (puerto 443) automáticamente
3. **No requiere intervención manual** - todo es transparente

El puerto 443 normalmente **no está bloqueado** porque se usa para tráfico web HTTPS.

## 🛠️ Desarrollo Local

Para trabajar con la landing page localmente:

```bash
# Clonar el repositorio
git clone https://github.com/Tech-and-Code/landing-provision.git
cd landing-provision

# Abrir en tu navegador
# Simplemente abre index.html en tu navegador
```

## 📝 Archivos Generados

Después de ejecutar el script de provisión, se generan:

- `.provision.conf` - Configuración guardada (URL repo, directorio, modo)
- `~/.ssh/config` - Configuración SSH para puerto 443 (si es necesario)
- Diversos archivos de configuración de Docker y servicios

## 🔄 Actualización del Script

Para obtener la última versión del script:

```bash
# Actualizar desde GitHub
git pull origin main

# O descargar manualmente
curl -O https://raw.githubusercontent.com/Tech-and-Code/landing-provision/main/scripts/provision-houseunity.sh
```

## 🤝 Contribuir

Si encuentras algún problema o tienes sugerencias:

1. Abre un issue en GitHub
2. Envía un pull request con mejoras
3. Documenta cualquier cambio significativo

## 📄 Licencia

Este proyecto está bajo la licencia MIT.
