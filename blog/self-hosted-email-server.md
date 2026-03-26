---
title: "Configurando un Servidor de Correo Self-Hosted con Docker"
date: "2026-03-26"
tags: ["docker", "email", "self-hosting", "traefik", "roundcube"]
---

# Configurando un Servidor de Correo Self-Hosted con Docker

Recientemente tomé la decisión de recuperar el control sobre mi infraestructura digital. Uno de los servicios más críticos —y a la vez más intimidantes— de implementar es un servidor de correo electrónico.

Este artículo documenta el proceso completo de configuración de un servidor de email auto-hosteado usando Docker, Traefik como reverse proxy, y Roundcube como webmail.

## El Desafío

Auto-hostear email tiene fama de ser complicado. Entre SPF, DKIM, DMARC, TLS, y la configuración de Postfix/Dovecot, hay muchas piezas que pueden salir mal. Además, está el problema de la entregabilidad: asegurarte de que tus correos no terminen en spam.

Mi objetivo era claro:
- **Correo funcional** con IMAP/SMTP estándar
- **Webmail moderno** accesible desde cualquier navegador
- **SSL automático** con Let's Encrypt
- **Seguro** con SPF, DKIM y DMARC configurados
- **Mantenible** — que pueda gestionarlo sin dolor

## La Solución: docker-mailserver + Roundcube + Traefik

Después de investigar varias opciones, me decanté por esta combinación:

| Componente | Función |
|------------|---------|
| [docker-mailserver](https://github.com/docker-mailserver/docker-mailserver) | SMTP/IMAP con OpenDKIM + SpamAssassin |
| Roundcube | Webmail moderno y familiar |
| Traefik | Reverse proxy con SSL automático |

## Arquitectura

```
                    ┌─────────────────────────────────────┐
                    │           Traefik (Reverse Proxy)   │
                    │  mail.cativo.dev → Webmail          │
                    │  SSL: Let's Encrypt                 │
                    └─────────────────┬───────────────────┘
                                      │
              ┌───────────────────────┼───────────────────────┐
              │                       │                       │
              ▼                       ▼                       ▼
    ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
    │   docker-mail   │   │   Roundcube     │   │   Traefik     │
    │   server        │   │   (Webmail)     │   │   (proxy)     │
    │                 │   │                 │   │               │
    │  - Postfix      │   │  - Elastic UI   │   │  - SSL        │
    │  - Dovecot      │   │  - Sieve        │   │  - Routing    │
    │  - OpenDKIM     │   │  - Contacts     │   │               │
    │  - SpamAssassin │   │                 │   │               │
    └─────────────────┘   └─────────────────┘   └─────────────────┘
```

## Configuración Paso a Paso

### 1. Estructura del Proyecto

```
mail-server/
├── docker-compose.yml
├── .env
├── docker-mailserver/
│   └── accounts/
│       ├── postfix-accounts.cf
│       └── dovecot-accounts.cf
└── scripts/
    └── setup-mail-accounts.sh
```

### 2. Docker Compose

El `docker-compose.yml` define dos servicios principales:

**Mail Server:**
```yaml
mail:
  image: ghcr.io/docker-mailserver/docker-mailserver:latest
  container_name: mail
  hostname: mail
  domainname: ${MAIL_DOMAIN}
  ports:
    - "25:25"      # SMTP
    - "465:465"    # SMTPS
    - "587:587"    # Submission (STARTTLS)
    - "993:993"    # IMAPS
  volumes:
    - mail-data:/var/mail
    - mail-state:/var/mail-state
    - mail-logs:/var/log/mail
    - mail-config:/tmp/docker-mailserver
    - ./docker-mailserver/accounts/postfix-accounts.cf:/tmp/docker-mailserver/postfix-accounts.cf:ro
    - ./docker-mailserver/accounts/dovecot-accounts.cf:/tmp/docker-mailserver/dovecot-accounts.cf:ro
    - /path/to/traefik/letsencrypt/acme.json:/etc/letsencrypt/acme.json:ro
  environment:
    - OVERRIDES_HOSTNAME=${MAIL_HOSTNAME:-mail}.${MAIL_DOMAIN}
    - SSL_TYPE=letsencrypt
    - ENABLE_SPAMASSASSIN=1
    - ENABLE_MANAGESIEVE=1
    - MAIL_ACCOUNTS=${MAIL_ACCOUNTS}
  networks:
    - web
  cap_add:
    - NET_ADMIN
    - SYS_PTRACE
```

**Webmail (Roundcube):**
```yaml
webmail:
  image: roundcube/roundcubemail:latest
  container_name: webmail
  environment:
    - ROUNDCUBEMAIL_DEFAULT_HOST=mail
    - ROUNDCUBEMAIL_DEFAULT_PORT=143
    - ROUNDCUBEMAIL_SMTP_SERVER=mail
    - ROUNDCUBEMAIL_SMTP_PORT=587
    - ROUNDCUBEMAIL_PLUGINS=archive,zipdownload,managesieve
  networks:
    - web
  volumes:
    - webmail-data:/var/roundcube/db
  entrypoint:
    - /bin/sh
    - -c
    - |
      mkdir -p /var/www/html/config &&
      echo '<?php
      $config["plugins"] = [];
      $config["imap_host"] = "mail:143";
      $config["smtp_host"] = "mail:587";
      $config["smtp_port"] = 587;
      $config["smtp_user"] = "%u";
      $config["smtp_pass"] = "%p";
      $config["smtp_auth_type"] = "PLAIN";
      $config["smtp_use_tls"] = true;
      $config["smtp_tls_wrapper"] = false;
      $config["db_dsnw"] = "sqlite:////var/roundcube/db/db.sqlite";
      $config["skin"] = "elastic";
      $config["imap_conn_options"]["ssl"]["verify_peer"] = false;
      $config["imap_conn_options"]["ssl"]["verify_peer_name"] = false;
      $config["smtp_conn_options"]["ssl"]["verify_peer"] = false;
      $config["smtp_conn_options"]["ssl"]["verify_peer_name"] = false;
      ' > /var/www/html/config/config.inc.php &&
      exec /docker-entrypoint.sh apache2-foreground
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.mail.rule=Host(`mail.${MAIL_DOMAIN}`)"
    - "traefik.http.routers.mail.entrypoints=websecure"
    - "traefik.http.routers.mail.tls.certresolver=letsencryptresolver"
    - "traefik.http.routers.mail.middlewares=mail-headers@file"
    - "traefik.http.services.mail.loadbalancer.server.port=80"
  depends_on:
    - mail
```

### 3. Variables de Entorno (.env)

```bash
MAIL_DOMAIN=tudominio.com
MAIL_HOSTNAME=mail
MAIL_ACCOUNTS=admin@tudominio.com|SecurePassword123|5000:5000
POSTFIX_MESSAGE_SIZE_LIMIT=52428800
TRAEFIK_ACME_PATH=/path/to/traefik/letsencrypt/acme.json
```

### 4. Configuración de Cuentas

Los archivos de cuentas usan hash SHA512-CRYPT:

**postfix-accounts.cf:**
```
admin@tudominio.com|{SHA512-CRYPT}$6$rounds=5000$salt$hashed_password
```

**dovecot-accounts.cf:**
```
admin@tudominio.com|{SHA512-CRYPT}$6$rounds=5000$salt$hashed_password:::::
```

### 5. Traefik Integration

El middleware de headers para Roundcube (`dynamic/auth.yml`):

```yaml
http:
  middlewares:
    mail-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        forceSTSHeader: true
        frameDeny: false  # Roundcube necesita frames para algunas funcionalidades
        contentTypeNosniff: true
        browserXssFilter: true
```

## Problemas Encontrados y Soluciones

### 1. Roundcube no podía escribir en la base de datos

**Problema:** Roundcube fallaba al intentar escribir en SQLite porque el contenedor corría como root pero los archivos pertenecían a www-data.

**Solución:** Usar un volumen externo para la base de datos y asegurar que el entrypoint cree la config antes de iniciar Apache.

### 2. SMTP Authentication no funcionaba

**Problema:** Roundcube intentaba usar TLS wrapper (puerto 465) en lugar de STARTTLS (puerto 587).

**Solución:** Configurar explícitamente en el entrypoint personalizado:
```php
$config["smtp_port"] = 587;
$config["smtp_auth_type"] = "PLAIN";
$config["smtp_tls_wrapper"] = false;
```

### 3. Los signos de dólar en el entrypoint se interpretaban como variables

**Problema:** Al usar un heredoc en el entrypoint, los `$config` se interpretaban como variables de shell.

**Solución:** Escapar los signos de dólar con `$$` en el docker-compose.yml.

### 4. CSP de Traefik bloqueaba funcionalidades de Roundcube

**Problema:** El header `frameDeny: true` rompía la interfaz de Roundcube.

**Solución:** Relajar CSP específicamente para el middleware de mail:
```yaml
frameDeny: false  # Roundcube usa frames internamente
```

## DNS Records Requeridos

Para que tu servidor sea entregable, necesitas configurar:

```dns
; MX Record
@           IN  MX      10 mail.tudominio.com.

; A Record
mail        IN  A       <IP-del-VPS>

; PTR Record (con tu proveedor VPS)
<ip>        IN  PTR     mail.tudominio.com.

; SPF
@           IN  TXT     "v=spf1 mx a ip4:<tu-ip> -all"

; DKIM (generado automáticamente por docker-mailserver)
mail._domainkey  IN  TXT     "v=DKIM1; h=sha256; k=rsa; p=..."

; DMARC (opcional pero recomendado)
_dmarc      IN  TXT     "v=DMARC1; p=quarantine; rua=mailto:postmaster@tudominio.com"
```

## Comandos Útiles

```bash
# Iniciar servicios
docker compose up -d

# Agregar cuenta de email
docker exec mail setup email add admin@tudominio.com 'password'

# Listar cuentas
docker exec mail setup email list

# Ver logs
docker compose logs -f mail

# Ver puertos activos
docker exec mail ss -tlnp | grep -E ':(25|465|587|993)'

# Reiniciar servicios
docker compose restart
```

## Script de Gestión de Cuentas

Para facilitar la administración, creé un script (`scripts/setup-mail-accounts.sh`):

```bash
#!/bin/bash
set -e

EMAIL=$1
PASSWORD=$2

# Verificar si el contenedor está corriendo
if ! docker ps --format '{{.Names}}' | grep -q "^mail$"; then
    echo "El contenedor 'mail' no está corriendo."
    exit 1
fi

# Agregar cuenta
docker exec mail setup email add "$EMAIL" "$PASSWORD"

if [ $? -eq 0 ]; then
    echo "Cuenta '$EMAIL' agregada exitosamente"
fi
```

Uso:
```bash
./scripts/setup-mail-accounts.sh admin@tudominio.com SecurePass123
```

## Seguridad

- **SSL/TLS:** Todos los puertos usan TLS (STARTTLS o TLS implícito)
- **SpamAssassin:** Filtrado de spam con ~90% de efectividad
- **OpenDKIM:** Firma de correos salientes
- **SPF:** Validación de remitentes
- **DMARC:** Política de autenticación
- **Contraseñas:** Hash SHA512-CRYPT con salt

## Lecciones Aprendidas

1. **No expongas puertos innecesarios:** Solo 25, 465, 587, y 993 son esenciales.

2. **Usa volúmenes persistentes:** `mail-data`, `mail-state`, y `mail-logs` deben sobrevivir a recreaciones del contenedor.

3. **Comparte acme.json con Traefik:** Esto permite que docker-mailserver use los certificados Let's Encrypt gestionados por Traefik.

4. **Red interna de Docker:** Roundcube y mail server deben estar en la misma red Docker para comunicarse directamente sin TLS público.

5. **ClamAV consume mucha RAM:** Si tienes menos de 4GB, considera deshabilitarlo.

## Estado Actual

El servidor está en producción y funcionando correctamente:

- ✅ Envío y recepción de correos
- ✅ Webmail accesible en https://mail.tudominio.com
- ✅ SSL automático con Let's Encrypt
- ✅ Filtrado de spam activo
- ✅ Filtros Sieve configurables desde webmail

## Próximos Pasos

- Configurar backups automáticos de mail-data
- Implementar monitoring con Prometheus
- Añadir soporte para aliases y dominios virtuales múltiples

## Conclusión

Auto-hostear email es más accesible de lo que parece. Con docker-mailserver y Traefik, la mayor parte de la complejidad está abstraída. El resultado es un servidor de correo seguro, funcional y bajo tu control total.

¿Vale la pena el esfuerzo? Para mí, sí. Recuperar la soberanía sobre mis comunicaciones digitales no tiene precio.

---

**Recursos:**
- [docker-mailserver docs](https://docker-mailserver.github.io/docker-mailserver/)
- [Roundcube docs](https://roundcube.net/)
- [Traefik docs](https://doc.traefik.io/traefik/)
- [MXToolbox](https://mxtoolbox.com/) — Para verificar tu configuración DNS
