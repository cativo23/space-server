# Docker Mail Server

Simple, production-ready mail server using docker-mailserver with Traefik integration.

## Quick Start

```bash
# 1. Copy environment file
cp .env.example .env

# 2. Edit with your domain and passwords
nano .env

# 3. Start the server
docker compose up -d

# 4. Check status
docker compose ps
```

## Access

| Service | URL |
|---------|-----|
| Webmail | `https://mail.cativo.dev` |

## Default Account

Set in `.env` as `MAIL_ACCOUNTS`:
```
email@domain.com|password|5000:5000
```

## DNS Records

```
; MX Record
@           IN  MX      10 mail.cativo.dev.

; A Record
mail        IN  A       <server-ip>

; PTR Record (with VPS provider)
<ip>        IN  PTR     mail.cativo.dev.

; SPF
@           IN  TXT     "v=spf1 mx a ip4:<server-ip> -all"

; DKIM (generate after first run)
; Run: docker exec mail docker-mailserver config dkim domain cativo.dev
; Copy the DNS record output

; DMARC
_dmarc      IN  TXT     "v=DMARC1; p=quarantine; rua=mailto:postmaster@cativo.dev"
```

## Common Commands

```bash
# View logs
docker compose logs -f mail

# Add email account
docker exec mail docker-mailserver config account add user@cativo.dev password123

# List accounts
docker exec mail docker-mailserver config account list

# Update password
docker exec mail docker-mailserver config account passwd user@cativo.dev newpassword

# Generate DKIM keys
docker exec mail docker-mailserver config dkim domain cativo.dev

# View mail queue
docker exec mail mailq

# Delete from queue
docker exec mail postsuper -d ALL

# Backup
docker compose exec mail tar czf /tmp/backup.tar.gz /var/mail /var/mail-state
docker compose cp mail:/tmp/backup.tar.gz ./backup.tar.gz
```

## Ports

| Port | Service |
|------|---------|
| 25   | SMTP (incoming) |
| 465  | SMTPS (secure submission) |
| 587  | Submission (STARTTLS) |
| 993  | IMAPS |
| 995  | POP3S (optional) |

## Features

- Postfix (MTA)
- Dovecot (IMAP/POP3)
- SpamAssassin (spam filtering)
- ClamAV (antivirus)
- Fail2Ban (intrusion prevention)
- Roundcube (webmail)
- ManageSieve (mail filters)
- Let's Encrypt SSL (via Traefik)

## Troubleshooting

```bash
# Check if ports are listening
docker exec mail ss -tlnp

# Test SMTP connection
telnet localhost 25

# Test secure connection
openssl s_client -connect localhost:465

# View specific logs
docker compose logs -f mail | grep -i error
```

## Resources

- [docker-mailserver docs](https://docker-mailserver.github.io/docker-mailserver/)
- [GitHub](https://github.com/docker-mailserver/docker-mailserver)
- [Roundcube docs](https://roundcube.net/about/)
