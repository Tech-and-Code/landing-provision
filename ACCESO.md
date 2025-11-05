# 📱 Guía de Acceso - HouseUnity

## 🚀 Inicio Rápido

### Ver toda la información de acceso

Ejecuta el script de información en cualquier momento:

```bash
bash scripts/show-info.sh
```

Este script te mostrará:
- 🌐 URLs de acceso a tu aplicación
- 🐳 Comandos Docker útiles
- 🗄️ Conexión a MySQL
- 💾 Información de respaldos
- 🔍 Comandos de debugging
- 🆘 Solución de problemas

---

## 🌐 Acceso Rápido a la Aplicación

### Desde Windows u otro PC

**Red Bridge/Host-only:**
```
Backend:  http://<IP_DE_LA_VM>:8080
Frontend: http://<IP_DE_LA_VM>:5173
```

**Red NAT (requiere Port Forwarding):**
```
Backend:  http://localhost:8080
Frontend: http://localhost:5173
```

### Obtener la IP de tu VM

Desde dentro de la VM ejecuta:
```bash
ip addr show | grep "inet " | grep -v "127.0.0.1"
```

---

## 🐳 Comandos Docker Esenciales

```bash
# Navegar al proyecto
cd ~/Tech-Code-Proyecto  # o la ruta donde clonaste

# Ver estado
docker compose ps

# Ver logs
docker compose logs -f

# Reiniciar
docker compose restart

# Detener
docker compose down

# Levantar
docker compose up -d

# Reconstruir después de cambios
docker compose up --build -d
```

---

## 🗄️ Conexión a MySQL

### Desde MySQL Workbench (Windows)

```
Connection Method: Standard (TCP/IP)
Hostname: <IP_DE_LA_VM>
Port: 3307 (Master) o 3308 (Slave)
Username: root
Password: [tu contraseña del .env]
```

### Desde línea de comandos en la VM

```bash
# Conectar a Master
docker exec -it houseunity-mysql-master mysql -u root -p

# Conectar a Slave
docker exec -it houseunity-mysql-slave mysql -u root -p
```

---

## 🔄 Replicación MySQL

Verificar estado de la replicación:

```bash
cd ~/Tech-Code-Proyecto/docker/scripts
./check-replication.sh
```

---

## 💾 Sistema de Respaldo (rsync)

### Sincronizar desde Windows/otro PC

```bash
# Guardar contraseña
echo 'TU_CONTRASEÑA' > rsync.pass
chmod 600 rsync.pass

# Descargar backups
rsync -av --port=873 --password-file=rsync.pass \
  backupuser@<IP_VM>::backups ./backup-local/

# Subir archivos
rsync -av --port=873 --password-file=rsync.pass \
  ./archivo.txt backupuser@<IP_VM>::backups
```

Ver contraseña de rsync:
```bash
sudo cat /etc/rsyncd.secrets
```

---

## 🔍 Debugging

### Verificar que todo está corriendo

```bash
# Ver contenedores
docker ps

# Ver puertos abiertos
ss -tulpn | grep -E '8080|5173|3307|3308|873'

# Probar backend localmente
curl http://localhost:8080

# Ver logs de un servicio específico
docker compose logs -f backend
```

### Contenedores importantes

- `houseunity-backend` - API Laravel
- `houseunity-frontend` - Aplicación web
- `houseunity-mysql-master` - Base de datos principal (escritura)
- `houseunity-mysql-slave` - Base de datos réplica (lectura)

---

## 🆘 Solución de Problemas

### No puedo acceder desde Windows

1. **Verificar contenedores:**
   ```bash
   docker compose ps
   ```

2. **Verificar puertos:**
   ```bash
   ss -tulpn | grep 8080
   ```

3. **Probar desde la VM:**
   ```bash
   curl http://localhost:8080
   ```

4. **Si usas NAT, configurar Port Forwarding en VirtualBox:**
   - Settings → Network → Port Forwarding
   - Host Port 8080 → Guest Port 8080
   - Host Port 5173 → Guest Port 5173

### Contenedores no inician

```bash
# Ver errores
docker compose logs

# Reconstruir
docker compose down
docker compose up --build -d
```

### MySQL no acepta conexiones

```bash
# Ver logs
docker logs houseunity-mysql-master

# Esperar 1-2 minutos si recién inició
```

### Cambios en código no se reflejan

```bash
# Reconstruir
docker compose up --build -d

# Limpiar caché Laravel
docker exec -it houseunity-backend php artisan cache:clear
docker exec -it houseunity-backend php artisan config:clear
```

---

## 📂 Archivos Importantes

```
~/Tech-Code-Proyecto/
├── .env                    # Configuración (contraseñas, URLs)
├── docker-compose.yml      # Definición de servicios
├── storage/logs/           # Logs de Laravel
├── public/uploads/         # Archivos subidos
└── docker/scripts/         # Scripts de utilidad
    ├── check-replication.sh
    └── ...

/export/                    # Directorio de backups (rsync)
```

---

## 📞 Recursos Adicionales

- **Script de información completa:** `bash scripts/show-info.sh`
- **Script de provisión:** `scripts/provision-houseunity.sh`
- **Configuración guardada:** `.provision.conf`

---

## 🔐 Seguridad

### Cambiar contraseñas en producción

Edita el archivo `.env` y cambia:
- `DB_PASSWORD`
- `MYSQL_ROOT_PASSWORD`
- Cualquier API key o secret

Luego reinicia los servicios:
```bash
docker compose down
docker compose up -d
```

### Firewall

El script de provisión configura automáticamente el firewall para:
- SSH (puerto 22 y 443)
- HTTP/HTTPS (80, 443)
- Backend (8080)
- Frontend (5173)

Puedes verificar con:
```bash
sudo ufw status          # Ubuntu/Debian
sudo firewall-cmd --list-all  # Rocky/CentOS
```

---

## 📝 Notas

- La primera vez que accedas a MySQL puede tardar 1-2 minutos en inicializar
- Los logs de Laravel están en `storage/logs/laravel.log`
- Para desarrollo, usa el puerto del Frontend (5173)
- Para producción, configura un servidor web (Nginx/Apache) que apunte al Backend

---

**¿Necesitas ayuda?** Ejecuta `bash scripts/show-info.sh` para ver toda la información de acceso actualizada.
