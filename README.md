# Space Server

> Mi infraestructura personal completamente self-hosteada. De una laptop vieja a un VPS en producción.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-ready-blue?logo=docker)](https://www.docker.com/)

## Por qué existe esto

Estaba cansado de depender de servicios de terceros para cosas básicas como email y hosting. Quería control total sobre mis datos y aprender cómo funciona realmente la infraestructura web moderna. Así que convertí una laptop vieja en un servidor casero y eventualmente lo migré a un VPS cuando el hardware ya no daba más.

Este repo documenta todo el proceso - los 30+ commits debuggeando el mail server, la migración completa con scripts automatizados, y las lecciones aprendidas en el camino.

## Qué corre aquí

**Producción actual:** Hetzner VPS (8GB RAM, Intel Xeon, Ubuntu 24.04)

```
15+ servicios containerizados:
├── Mail server completo (docker-mailserver + Roundcube)
├── Blog técnico (Ghost + MySQL)
├── Portfolio personal (React + Laravel API)
├── Monitoring (Grafana + Prometheus + Uptime Kuma)
├── Logs centralizados (Dozzle)
└── Traefik manejando SSL automático para todo
```

**Migración:** 12 minutos de downtime total para mover todo desde la laptop. Ver [el blog post](blog/migracion-servidor-completa.md) para el proceso completo con scripts.

## Stack técnico

No voy a listar cada contenedor aquí - el punto es que todo está dockerizado y orquestado con docker-compose. Si quieres ver exactamente qué imágenes uso, revisa los `docker-compose.yml` en cada directorio.

**Lo importante:**
- **Traefik v3.6** - Reverse proxy que maneja SSL automático con Let's Encrypt
- **docker-mailserver** - SMTP/IMAP con SPF, DKIM, DMARC configurados
- **Ghost 5** - Blog donde documento todo esto
- **Grafana + Prometheus** - Para saber cuándo algo se rompe antes de que me entere por Twitter

## Empezar rápido

```bash
# Clonar
git clone https://github.com/cativo23/space-server.git
cd space-server

# Configurar
cp .env.example .env
# Editar .env con tu dominio y credenciales

# Levantar servicios
docker compose up -d
```

**Nota importante:** Si vas a usar el mail server, necesitas configurar DNS correctamente (registros MX, SPF, DKIM). Ver [la guía del mail server](blog/self-hosted-email-server.md) que documenta los 30+ commits que me tomó hacerlo funcionar.

## Documentación real

Escribí blog posts técnicos sobre el proceso porque la documentación genérica no me sirvió cuando lo estaba haciendo:

- **[Configurando un Servidor de Correo Self-Hosted](blog/self-hosted-email-server.md)** - Setup completo del mail server. Incluye todos los errores que encontré y cómo los resolví.

- **[Migración Completa: De Laptop a VPS](blog/migracion-servidor-completa.md)** - Cómo migré 15+ servicios con scripts automatizados. 12 minutos de downtime, cero pérdida de datos.

- **[Debugging Gateway Timeout en Webmail](blog/debugging-webmail-gateway-timeout.md)** - Deep-dive técnico del debugging post-migración. Network mismatch y permisos.

## Cosas que aprendí

**Lo que funcionó:**
- Scripts de migración automatizados valen completamente la pena
- Traefik hace que SSL sea trivial
- Docker Compose es suficiente para esto, no necesitas Kubernetes

**Lo que no funcionó:**
- Hetzner bloquea el puerto 25 saliente (no puedo enviar emails directamente)
- Los volúmenes Docker migrados pueden tener permisos incorrectos
- Las redes Docker no son portables entre hosts

**Próximos pasos:**
- Migrar a Ansible para hacer esto más reproducible
- Eventualmente comprar un servidor físico dedicado
- Configurar un relay SMTP para poder enviar emails

## Estructura del repo

```
space-server/
├── docker-compose.yml          # Stack principal
├── mail-server/                # Configuración del mail server
│   ├── docker-compose.yml
│   └── docker-mailserver/      # Configs de Postfix/Dovecot
├── traefik/                    # Reverse proxy + SSL
├── scripts/                    # Scripts de migración
│   ├── 1-backup-cativo.sh
│   ├── 2-download-backup.sh
│   └── ...
└── blog/                       # Posts técnicos (no commiteados)
```

## Requisitos

- VPS con al menos 4GB RAM (8GB recomendado)
- Dominio con acceso a DNS
- Docker + Docker Compose v2
- Puerto 25 abierto si quieres enviar emails (muchos VPS lo bloquean)

## Contribuir

Este es principalmente un proyecto personal, pero si encuentras algo útil o quieres sugerir mejoras, los PRs son bienvenidos. Ver [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT - Haz lo que quieras con esto. Si te sirve, genial.

---

**¿Preguntas?** Abre un issue o revisa los blog posts - probablemente ya documenté el problema que estás teniendo.
