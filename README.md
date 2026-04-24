# Space Server

> My completely self-hosted personal infrastructure. From an old laptop to a production VPS.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-ready-blue?logo=docker)](https://www.docker.com/)

## Why this exists

I was tired of depending on third-party services for basic things like email and hosting. I wanted full control over my data and to learn how modern web infrastructure actually works. So I turned an old laptop into a home server and eventually migrated it to a VPS when the hardware couldn't keep up anymore.

This repo documents the entire process - the 30+ commits debugging the mail server, the complete migration with automated scripts, and the lessons learned along the way.

## What runs here

**Current production:** Hetzner VPS (8GB RAM, Intel Xeon, Ubuntu 24.04)

```
15+ containerized services:
├── Complete mail server (docker-mailserver + Roundcube)
├── Technical blog (Ghost + MySQL)
├── Personal portfolio (React + Laravel API)
├── Monitoring (Grafana + Prometheus + Uptime Kuma)
├── Centralized logs (Dozzle)
└── Traefik handling automatic SSL for everything
```

**Migration:** 12 minutes of total downtime to move everything from the laptop. See [the blog post](blog/migracion-servidor-completa.md) for the complete process with scripts.

## Tech stack

I'm not going to list every container here - the point is that everything is dockerized and orchestrated with docker-compose. If you want to see exactly what images I use, check the `docker-compose.yml` files in each directory.

**What matters:**
- **Traefik v3.6** - Reverse proxy that handles automatic SSL with Let's Encrypt
- **docker-mailserver** - SMTP/IMAP with SPF, DKIM, DMARC configured
- **Ghost 5** - Blog where I document all of this
- **Grafana + Prometheus** - To know when something breaks before I find out on Twitter

## Quick start

```bash
# Clone
git clone https://github.com/cativo23/space-server.git
cd space-server

# Configure
cp .env.example .env
# Edit .env with your domain and credentials

# Start services
docker compose up -d
```

**Important note:** If you're going to use the mail server, you need to configure DNS correctly (MX, SPF, DKIM records). See [the mail server guide](blog/self-hosted-email-server.md) that documents the 30+ commits it took me to get it working.

## Real documentation

I wrote technical blog posts about the process because generic documentation didn't help me when I was doing this:

- **[Setting Up a Self-Hosted Email Server](blog/self-hosted-email-server.md)** - Complete mail server setup. Includes all the errors I found and how I fixed them.

- **[Complete Migration: From Laptop to VPS](blog/migracion-servidor-completa.md)** - How I migrated 15+ services with automated scripts. 12 minutes of downtime, zero data loss.

- **[Debugging Gateway Timeout in Webmail](blog/debugging-webmail-gateway-timeout.md)** - Technical deep-dive of post-migration debugging. Network mismatch and permissions.

## Things I learned

**What worked:**
- Automated migration scripts are completely worth it
- Traefik makes SSL trivial
- Docker Compose is enough for this, you don't need Kubernetes

**What didn't work:**
- Hetzner blocks outbound port 25 (I can't send emails directly)
- Migrated Docker volumes can have incorrect permissions
- Docker networks aren't portable between hosts

**Next steps:**
- Migrate to Ansible to make this more reproducible
- Eventually buy a dedicated physical server
- Set up an SMTP relay to be able to send emails

## Repo structure

```
space-server/
├── docker-compose.yml          # Main stack
├── mail-server/                # Mail server configuration
│   ├── docker-compose.yml
│   └── docker-mailserver/      # Postfix/Dovecot configs
├── traefik/                    # Reverse proxy + SSL
├── scripts/                    # Migration scripts
│   ├── 1-backup-cativo.sh
│   ├── 2-download-backup.sh
│   └── ...
└── blog/                       # Technical posts (not committed)
```

## Requirements

- VPS with at least 4GB RAM (8GB recommended)
- Domain with DNS access
- Docker + Docker Compose v2
- Port 25 open if you want to send emails (many VPS providers block it)

## Contributing

This is mainly a personal project, but if you find something useful or want to suggest improvements, PRs are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT - Do whatever you want with this. If it helps you, great.

---

**Questions?** Open an issue or check the blog posts - I probably already documented the problem you're having.
