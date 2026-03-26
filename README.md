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

**Infraestructura personal auto-hosteada**

</div>

---

## Overview

Space Server es una colección de servicios self-hosteados que reemplazan dependencias de Big Tech con alternativas bajo tu control total. Nace de la necesidad de soberanía digital: tus correos, tu contenido y tus datos en tu infraestructura.

Actualmente incluye servidor de correo completo con webmail y blog técnico, con más servicios en desarrollo.

---

## ✨ Features

- **Email Server Completo** — Postfix + Dovecot con SPF, DKIM, DMARC configurados
- **SSL Automático** — Certificados Let's Encrypt gestionados por Traefik
- **Webmail Roundcube** — Interfaz web con filtros Sieve y gestión de contactos
- **Anti-Spam Integrado** — SpamAssassin con ~90% de efectividad
- **Blog Técnico** — Contenido sobre self-hosting y desarrollo
- **Docker Native** — Todo contenerizado, desplegable en cualquier VPS

---

## 🛠 Tech Stack

| Componente | Versión | Propósito |
|------------|---------|-----------|
| Docker Mail Server | latest | SMTP/IMAP con OpenDKIM + SpamAssassin |
| Roundcube | latest | Webmail moderno |
| Traefik | latest | Reverse proxy con SSL automático |
| Docker Compose | v2+ | Orquestación de servicios |

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
