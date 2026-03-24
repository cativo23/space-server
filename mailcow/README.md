# Mailcow Email Server

Minimal Mailcow setup using existing Traefik and dockerproxy.

## Quick Start

```bash
# 1. Copy environment file
cp .env.example .env

# 2. Edit .env
nano .env

# 3. Start Mailcow
docker compose up -d

# 4. Watch logs
docker compose logs -f
```

## Access

| Service | URL |
|---------|-----|
| Webmail | `https://mail.cativo.dev` |

## Default Login

- **Username:** `admin`
- **Password:** `moohoo`

**Change it immediately after first login!**

## DNS Records

```
; MX
@    IN    MX    10 mail.cativo.dev.

; A
mail    IN    A    <server-ip>

; PTR (with VPS provider)
<ip>    IN    PTR    mail.cativo.dev.

; SPF
@    IN    TXT    "v=spf1 mx a ip4:<server-ip> -all"

; DMARC
_dmarc    IN    TXT    "v=DMARC1; p=quarantine"
```

After first run, get DKIM from Admin UI and add as DNS TXT record.

## Ports

| Port | Service |
|------|---------|
| 25   | SMTP (required for receiving) |
| 465  | SMTPS |
| 587  | Submission |
| 993  | IMAPS |

## Commands

```bash
# Status
docker compose ps

# Logs
docker compose logs -f

# Restart
docker compose restart

# Backup DB
docker compose exec mysql-mailcow mysqldump -u root -p${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE} > backup.sql
```
