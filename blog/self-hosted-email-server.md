---
title: "Configurando un Servidor de Correo Self-Hosted con Docker"
date: "2026-03-26"
tags: ["docker", "email", "self-hosting", "traefik", "roundcube"]
---

# Configurando un Servidor de Correo Self-Hosted con Docker

Recientemente tomé la decisión de recuperar el control sobre mi infraestructura digital. Uno de los servicios más críticos —y a la vez más intimidantes— de implementar es un servidor de correo electrónico.

Este artículo documenta el proceso **real y completo** de configuración de un servidor de email auto-hosteado usando Docker, Traefik como reverse proxy, y Roundcube como webmail. Incluye todos los problemas que enfrentamos commit a commit y cómo los resolvimos.

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

## El Viaje: 30+ Commits hasta la Configuración Final

Esta no fue una implementación lineal. Fueron **más de 30 commits** de prueba y error. Aquí está la historia completa:

### Commit 1: Implementación Inicial (2896448)

Empezamos con docker-mailserver intentando usar los certificados de Traefik directamente:

```yaml
# Primer intento - SSL_TYPE=letsencrypt
volumes:
  - ../traefik/letsencrypt:/etc/letsencrypt:ro
environment:
  - SSL_TYPE=letsencrypt
```

**Problema:** docker-mailserver esperaba una estructura de archivos diferente a la de Traefik.

### Commit 2-3: SSL Manual con Traefik (4c29fe3, b2369db)

Intentamos usar SSL manual apuntando a los certificados de Traefik:

```yaml
environment:
  - SSL_TYPE=manual
  - SSL_CERT_PATH=/etc/letsencrypt/live/cativo.dev/fullchain.pem
  - SSL_KEY_PATH=/etc/letsencrypt/live/cativo.dev/privkey.pem
```

**Problema:** Los paths no coincidían y la estructura de directorios era diferente.

### Commit 4: Self-Signed para Interno, Traefik para Público (7846a4a)

**Solución clave:** Dejamos que docker-mailserver genere certificados self-signed para la comunicación interna, y Traefik maneja el SSL público para el webmail:

```yaml
# Solución final
environment:
  # Sin SSL_TYPE - que genere self-signed para interno
  - PERMIT_DOCKER=network
```

Esta fue una decisión arquitectónica importante: **el tráfico entre conteneders es interno y privado**, no necesita Let's Encrypt. Solo el tráfico público (web → webmail) necesita SSL real.

### Commits 5-8: La Saga de Roundcube TLS (f902785, 9667ab5, 64e30b5, 77b9d08)

**Problema:** Roundcube intentaba conectarse al mail server con TLS, pero como era una red Docker interna, fallaba.

**Primer intento:** Deshabilitar TLS con variables de entorno:
```yaml
environment:
  - ROUNDCUBEMAIL_DEFAULT_IMAP_TLS=
  - ROUNDCUBEMAIL_DEFAULT_SMTP_TLS=
```

**Segundo intento:** Configurar explícitamente hosts y puertos:
```yaml
environment:
  - ROUNDCUBEMAIL_DEFAULT_HOST=mail
  - ROUNDCUBEMAIL_DEFAULT_PORT=143
  - ROUNDCUBEMAIL_SMTP_SERVER=mail
  - ROUNDCUBEMAIL_SMTP_PORT=587
```

**Tercer intento:** Config file personalizado:
```php
// roundcube-custom.conf.php
$config['imap_host'] = 'mail:143';
$config['smtp_host'] = 'mail:587';
$config['imap_conn_options'] = null;
$config['smtp_conn_options'] = null;
```

### Commits 9-12: Mount Paths y Config Files (64fd5e2, 1d0a25e, 31059e1, 7616503)

Probamos diferentes formas de montar la configuración:

```yaml
# Intento 1: custom.config.php
volumes:
  - ./roundcube-custom.conf.php:/var/roundcube/config/custom.config.php:ro

# Intento 2: config.inc.php
volumes:
  - ./roundcube-custom.conf.php:/var/roundcube/config/config.inc.php:ro

# Intento 3: config.docker.inc.php
volumes:
  - ./roundcube-docker.conf.php:/var/www/html/config/config.docker.inc.php:ro
```

### Commits 13-16: El Entry Point Personalizado (c23b8f3, 384e19c, 59bab0e, 6296d8d)

**Problema crítico:** Los archivos montados como volúmenes no funcionaban porque el entrypoint de Roundcube los sobrescribía.

**Solución:** Crear un entrypoint personalizado que escriba la configuración ANTES de que el entrypoint original se ejecute:

```yaml
entrypoint: /bin/sh -c
command:
  - |
    echo '<?php
    $config["plugins"] = [];
    $config["imap_host"] = "mail:143";
    $config["smtp_host"] = "mail:587";
    $config["smtp_port"] = 587;
    $config["db_dsnw"] = "sqlite:////var/roundcube/db/db.sqlite";
    $config["skin"] = "elastic";
    ' > /var/www/html/config/config.docker.inc.php
    exec /docker-entrypoint.sh apache2-foreground
```

### Commit 17: Permisos de Escritura (2e9257f)

**Problema:** Roundcube no podía escribir en la base de datos SQLite.

**Solución:** Ejecutar el contenedor como www-data:
```yaml
user: "www-data:www-data"
```

### Commits 18-21: Autenticación SMTP (f8a3f55, 91ec716, adc7997, 3fe6636)

**Problema:** Roundcube no podía enviar correos porque la autenticación SMTP no estaba configurada correctamente.

**Evolución de la configuración:**

```php
// Paso 1: Agregar smtp_user y smtp_pass
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';

// Paso 2: Tipo de autenticación explícito
$config['smtp_auth_type'] = 'PLAIN';

// Paso 3: STARTTLS (no TLS wrapper)
$config["smtp_use_tls"] = true;
$config["smtp_tls_wrapper"] = false;
```

El entrypoint final quedó así:

```yaml
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
    ' > /var/www/html/config/config.inc.php &&
    exec /docker-entrypoint.sh apache2-foreground
```

### Commits 22-24: Escape de Signos de Dólar (7c57b34, d720485)

**Problema:** En docker-compose.yml, los signos `$` se interpretaban como variables de entorno de shell.

**Solución:** Escapar con `$$`:

```yaml
# INCORRECTO (se interpreta como variable shell)
echo '$config["plugins"] = [];'

# CORRECTO (los $$ se convierten en $ en el output)
echo '$$config["plugins"] = [];';
```

### Commits 25-27: Cuentas de Email con Hash (d6a6fcf, 6d54dd4, dc016c0, 0afbf78)

**Problema:** Las contraseñas en texto plano no son seguras.

**Solución:** Usar archivos de configuración con hash SHA512-CRYPT:

```yaml
# docker-compose.yml
volumes:
  - ./docker-mailserver/accounts/postfix-accounts.cf:/tmp/docker-mailserver/postfix-accounts.cf:ro
  - ./docker-mailserver/accounts/dovecot-accounts.cf:/tmp/docker-mailserver/dovecot-accounts.cf:ro
```

```
# postfix-accounts.cf
admin@cativo.dev|{SHA512-CRYPT}$6$rounds=5000$salt$hashed_password

# dovecot-accounts.cf (mismo formato con ::::: al final)
admin@cativo.dev|{SHA512-CRYPT}$6$rounds=5000$salt$hashed_password:::::
```

Para generar el hash:
```bash
docker exec mail addmailuser admin@tudominio.com 'password'
# Luego copiar el hash generado a los archivos .cf
```

### Commits 28-29: CSP y Headers de Seguridad (ba1f9a0, a869652)

**Problema:** El Content Security Policy (CSP) de Traefik bloqueaba funcionalidades de Roundcube.

**Solución 1:** Crear middleware específico para mail sin `frameDeny`:

```yaml
# traefik/dynamic/auth.yml
http:
  middlewares:
    mail-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        forceSTSHeader: true
        frameDeny: false  # Roundcube necesita frames
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        contentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; frame-src 'self';"
```

**Solución 2:** Relajar CSP para Roundcube:
```yaml
contentSecurityPolicy: "default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; frame-ancestors *;"
```

### Commit 30: Script de Gestión de Cuentas (05b8a49)

Para facilitar la administración, creamos un script:

```bash
#!/bin/bash
# scripts/setup-mail-accounts.sh
set -e

EMAIL=$1
PASSWORD=$2

if ! docker ps --format '{{.Names}}' | grep -q "^mail$"; then
    echo "El contenedor 'mail' no está corriendo."
    exit 1
fi

docker exec mail setup email add "$EMAIL" "$PASSWORD"

if [ $? -eq 0 ]; then
    echo "Cuenta '$EMAIL' agregada exitosamente"
fi
```

## Configuración Final

### docker-compose.yml

```yaml
services:
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
    environment:
      - OVERRIDES_HOSTNAME=${MAIL_HOSTNAME:-mail}.${MAIL_DOMAIN}
      - SSL_TYPE=letsencrypt
      - ENABLE_SPAMASSASSIN=1
      - ENABLE_MANAGESIEVE=1
      - POSTFIX_MESSAGE_SIZE_LIMIT=${POSTFIX_MESSAGE_SIZE_LIMIT:-52428800}
      - LOG_LEVEL=info
    networks:
      - web
    cap_add:
      - NET_ADMIN
      - SYS_PTRACE

  webmail:
    image: roundcube/roundcubemail:latest
    container_name: webmail
    networks:
      - web
    entrypoint:
      - /bin/sh
      - -c
      - |
        mkdir -p /var/www/html/config &&
        echo '<?php
        $$config["plugins"] = [];
        $$config["imap_host"] = "mail:143";
        $$config["smtp_host"] = "mail:587";
        $$config["smtp_port"] = 587;
        $$config["smtp_user"] = "%u";
        $$config["smtp_pass"] = "%p";
        $$config["smtp_auth_type"] = "PLAIN";
        $$config["smtp_use_tls"] = true;
        $$config["smtp_tls_wrapper"] = false;
        $$config["db_dsnw"] = "sqlite:////var/roundcube/db/db.sqlite";
        $$config["skin"] = "elastic";
        $$config["imap_conn_options"]["ssl"]["verify_peer"] = false;
        $$config["imap_conn_options"]["ssl"]["verify_peer_name"] = false;
        $$config["smtp_conn_options"]["ssl"]["verify_peer"] = false;
        $$config["smtp_conn_options"]["ssl"]["verify_peer_name"] = false;
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

networks:
  web:
    external: true
```

### .env

```bash
MAIL_DOMAIN=tudominio.com
MAIL_HOSTNAME=mail
MAIL_ACCOUNTS=admin@tudominio.com|SecurePassword123|5000:5000
POSTFIX_MESSAGE_SIZE_LIMIT=52428800
```

## DNS Records Requeridos

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

## Lecciones Aprendidas

1. **No expongas puertos innecesarios:** Solo 25, 465, 587, y 993 son esenciales.

2. **Usa volúmenes persistentes:** `mail-data`, `mail-state`, y `mail-logs` deben sobrevivir a recreaciones del contenedor.

3. **Red interna de Docker:** Roundcube y mail server deben estar en la misma red Docker para comunicarse directamente sin TLS público.

4. **El entrypoint de Roundcube sobrescribe configuración:** Si necesitas configuración personalizada, debes escribirla ANTES de que el entrypoint original se ejecute.

5. **Escapar signos de dólar en docker-compose:** Usa `$$` en lugar de `$` dentro de scripts heredoc.

6. **ClamAV consume mucha RAM:** Si tienes menos de 4GB, considera deshabilitarlo.

7. **CSP puede bloquear webmail:** Relaja las políticas de seguridad específicamente para el middleware del mail.

## Estado Actual

El servidor está en producción y funcionando correctamente:

- ✅ Envío y recepción de correos
- ✅ Webmail accesible en https://mail.tudominio.com
- ✅ SSL automático con Let's Encrypt para tráfico público
- ✅ Filtrado de spam activo (~90% efectividad)
- ✅ Filtros Sieve configurables desde webmail
- ✅ Autenticación SMTP con STARTTLS

## Próximos Pasos

- Configurar backups automáticos de mail-data
- Implementar monitoring con Prometheus
- Añadir soporte para aliases y dominios virtuales múltiples

## Conclusión

Auto-hostear email es más accesible de lo que parece, pero requiere paciencia. Los 30+ commits de este proyecto demuestran que incluso con herramientas bien documentadas como docker-mailserver, hay detalles que solo se descubren probando.

El resultado final es un servidor de correo seguro, funcional y bajo tu control total. ¿Vale la pena el esfuerzo? Para mí, sí. Recuperar la soberanía sobre mis comunicaciones digitales no tiene precio.

---

**Recursos:**
- [docker-mailserver docs](https://docker-mailserver.github.io/docker-mailserver/)
- [Roundcube docs](https://roundcube.net/)
- [Traefik docs](https://doc.traefik.io/traefik/)
- [MXToolbox](https://mxtoolbox.com/) — Para verificar tu configuración DNS
