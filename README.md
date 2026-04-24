```
  _____ ____  ___   ____________   _____ __________ _    ____________
  / ___// __ \/   | / ____/ ____/  / ___// ____/ __ \ |  / / ____/ __ \
  \__ \/ /_/ / /| |/ /   / __/     \__ \/ __/ / /_/ / | / / __/ / /_/ /
 ___/ / ____/ ___ / /___/ /___    ___/ / /___/ _, _/| |/ / /___/ _, _/
/____/_/   /_/  |_\____/_____/   /____/_____/_/ |_| |___/_____/_/ |_|

              [ Self-hosted Email • Blog • Servicios Personales ]
```

<div align="center">

[![Status: Active](https://img.shields.io/badge/status-active-success)](https://github.com/cativo23/space-server)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-ready-blue?logo=docker)](https://www.docker.com/)
[![Self-hosted](https://img.shields.io/badge/self--hosted-100%25-orange)](.)

**Infraestructura personal auto-hosteada con 15+ servicios en producción**

[Features](#-features) • [Tech Stack](#-tech-stack) • [Quick Start](#-quick-start) • [Documentation](#-documentation) • [Blog Posts](#-blog-posts)

</div>

---

## 📖 Overview

Space Server es mi infraestructura personal completamente self-hosteada que reemplaza dependencias de Big Tech con alternativas bajo control total. Nace de la necesidad de soberanía digital: tus correos, tu contenido y tus datos en tu infraestructura.

**Actualmente en producción:**
- 🖥️ VPS Hetzner (8GB RAM, Intel Xeon, Ubuntu 24.04)
- 🐳 15+ servicios containerizados con Docker
- 🔒 SSL automático con Let's Encrypt
- 📊 Monitoring completo con Grafana + Prometheus
- ✉️ Mail server completo con webmail
- 📝 Blog técnico con Ghost
- 🎨 Portfolio personal con API Laravel

**Migrado exitosamente desde una laptop vieja** con 12 minutos de downtime total. Ver [blog de migración](blog/migracion-servidor-completa.md) para el proceso completo.

---

## ✨ Features

- **Email Server Completo** — Postfix + Dovecot con SPF, DKIM, DMARC configurados
- **SSL Automático** — Certificados Let's Encrypt gestionados por Traefik
- **Webmail Roundcube** — Interfaz web con filtros Sieve y gestión de contactos
- **Anti-Spam Integrado** — SpamAssassin con ~90% de efectividad
- **Blog & Portfolio** — Ghost blog + Portfolio personal con API Laravel
- **Monitoring Stack** — Grafana + Prometheus + Uptime Kuma para observabilidad completa
- **Logs Centralizados** — Dozzle para visualización de logs en tiempo real
- **Docker Native** — 15+ servicios contenerizados, desplegables en cualquier VPS

---

## 🛠 Tech Stack

### Core Infrastructure
| Container | Image | Purpose |
|-----------|-------|---------|
| traefik | `traefik:v3.6` | Reverse proxy con SSL automático |
| dockerproxy | `tecnativa/docker-socket-proxy:latest` | Docker socket proxy para seguridad |

### Applications
| Container | Image | Purpose |
|-----------|-------|---------|
| ghost-blog-prod-ghost-1 | `ghost:5-alpine` | Blog técnico |
| ghost-blog-prod-db-1 | `mysql:5.7` | Base de datos Ghost |
| portfolio-prod-app-1 | `cativo23/portfolio:latest` | Portfolio frontend (React) |
| portfolio-api-deploy-api-1 | `cativo23/portfolio-api:latest` | Portfolio API (Laravel) |
| portfolio-api-deploy-mysql-1 | `mariadb:10.11` | Base de datos Portfolio |
| portfolio-api-deploy-redis-1 | `redis:7-alpine` | Cache Redis |
| hello-kitty-landing-app-1 | `cativo23/hello-kitty-landing:latest` | Landing page |
| whoami | `traefik/whoami` | Test service |

### Mail Services
| Container | Image | Purpose |
|-----------|-------|---------|
| mail | `ghcr.io/docker-mailserver/docker-mailserver:latest` | SMTP/IMAP server |
| webmail | `roundcube/roundcubemail:latest` | Webmail interface |

### Monitoring & Observability
| Container | Image | Purpose |
|-----------|-------|---------|
| grafana | `grafana/grafana` | Dashboards y visualización |
| prometheus | `prom/prometheus` | Métricas y alertas |
| uptime-kuma | `louislam/uptime-kuma:2` | Monitoreo de uptime |
| dozzle | `amir20/dozzle:latest` | Logs en tiempo real |

---

## 📝 Blog Posts

Documentación técnica detallada del proceso de construcción y migración:

| Post | Descripción | Fecha |
|------|-------------|-------|
| [Configurando un Servidor de Correo Self-Hosted](blog/self-hosted-email-server.md) | Setup completo del mail server con docker-mailserver + Roundcube. Incluye 30+ commits de debugging. | 2026-03-26 |
| [Migración Completa de Servidor: De Laptop a VPS](blog/migracion-servidor-completa.md) | Proceso completo de migración con scripts automatizados. 15+ servicios, 12 minutos de downtime. | 2026-04-23 |
| [Debugging Gateway Timeout en Webmail](blog/debugging-webmail-gateway-timeout.md) | Deep-dive técnico del debugging post-migración. Network mismatch y permisos. | 2026-04-23 |

---

## 🚀 Quick Start

```bash
# 1. Clonar repositorio
git clone https://github.com/cativo23/space-server.git
cd space-server/mail-server

# 2. Configurar entorno
cp .env.example .env
# Editar con tu dominio y credenciales

# 3. Iniciar servicios
docker compose up -d

# 4. Acceder
# Webmail: https://mail.tudominio.com
```

---

## 📐 Architecture

```
space-server/
├── mail-server/              # Servidor de correo
│   ├── docker-compose.yml    # Mail + Roundcube + Traefik
│   ├── docker-mailserver/    # Configuración Postfix/Dovecot
│   └── scripts/              # Utilidades de gestión
└── blog/                     # Blog técnico
    └── self-hosted-email-server.md
```

**Flujo de Email:**
```
Internet → Traefik (SSL) → docker-mailserver (SMTP/IMAP)
                          → Roundcube (Webmail UI)
```

---

## 📚 Documentation

| Documento | Descripción |
|-----------|-------------|
| [mail-server/README.md](mail-server/README.md) | Guía completa del servidor de correo |
| [blog/self-hosted-email-server.md](blog/self-hosted-email-server.md) | Tutorial paso a paso |
| [CONTRIBUTING.md](mail-server/CONTRIBUTING.md) | Guía de contribución |

---

## 🧪 Testing

```bash
# Verificar estado de servicios
docker compose ps

# Ver logs
docker compose logs -f mail

# Enviar correo de prueba
docker exec mail sendmail tu-email@gmail.com <<EOF
Subject: Test desde Space Server
Funciona!
EOF

# Verificar puertos
docker exec mail ss -tlnp | grep -E ':(25|465|587|993)'
```

---

## 📦 Deployment

### Requisitos

| Requisito | Descripción |
|-----------|-------------|
| VPS | 2GB RAM mínimo (4GB recomendado) |
| Dominio | Con acceso a configuración DNS |
| Puerto 25 | Abierto (algunos VPS lo bloquean) |
| Docker | Docker + Docker Compose v2 |

### DNS Records

| Tipo | Nombre | Contenido |
|------|--------|-----------|
| A | `mail` | `<IP-del-VPS>` |
| MX | `@` | `mail.tudominio.com` (10) |
| TXT | `@` | `v=spf1 mx a:mail.tudominio.com -all` |
| TXT | `_dmarc` | `v=DMARC1; p=none` |
| TXT | `mail._domainkey` | `v=DKIM1; h=sha256; k=rsa; p=...` |

Ver [mail-server/README.md](mail-server/README.md) para detalles de producción.

---

## License

[MIT License](mail-server/LICENSE) — Self-host your digital life 🚀
