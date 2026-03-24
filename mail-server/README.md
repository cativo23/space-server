# Mail Server

Docker mail server with Traefik integration for cativo.dev.

## Services

| Service | URL | Description |
|---------|-----|-------------|
| Webmail | `https://mail.cativo.dev` | Roundcube webmail |

## Email Accounts

| Email | Password |
|-------|----------|
| admin@cativo.dev | `Qx9#mKp2$vL7nR4w` |
| test@cativo.dev | `TestPass123!` |

## DNS Records

Add these to your domain's DNS:

```
; MX Record
@           IN  MX      10 mail.cativo.dev.

; A Record
mail        IN  A       <server-ip>

; PTR Record (with VPS provider)
<ip>        IN  PTR     mail.cativo.dev.

; SPF
@           IN  TXT     "v=spf1 mx a ip4:<server-ip> -all"

; DMARC (optional)
_dmarc      IN  TXT     "v=DMARC1; p=quarantine; rua=mailto:postmaster@cativo.dev"
```

## Quick Start

```bash
cd ~/space-server/mail-server
docker compose up -d
```

## Common Commands

```bash
# Add email account
docker exec mail addmailuser user@cativo.dev 'password'

# List accounts
docker exec mail docker-mailserver config account list

# Delete account
docker exec mail delmailuser user@cativo.dev

# View logs
docker compose logs -f mail

# Restart
docker compose restart
```

## Ports

| Port | Service |
|------|---------|
| 25   | SMTP (incoming) |
| 465  | SMTPS |
| 587  | Submission |
| 993  | IMAPS |
| 995  | POP3S |

## Notes

- SSL is self-signed (Traefik handles public HTTPS for webmail)
- ClamAV disabled to reduce resource usage
- SpamAssassin enabled
