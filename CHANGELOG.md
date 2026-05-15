# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — observability and reliability

- Prometheus + Alertmanager + node_exporter + cAdvisor stack, with 8 alert rules across host (disk >85%/95%, memory >90%, load > 2× CPU count), containers (restart loop, missing), TLS (cert <14d), and scrape-up
- `alertmanager-discord` adapter forwarding alerts to a Discord webhook channel
- Three Grafana dashboards provisioned from JSON files: Node Exporter Full (1860), Traefik 3 Standalone (17346), cAdvisor (14282); Prometheus datasource also provisioned with a stable UID
- SMTP relay via Resend free tier (`DEFAULT_RELAY_HOST` + per-host sasl) — outbound mail now works despite Hetzner blocking port 25
- `IMPROVEMENT-PLAN.md` tracking architecture findings (P0–P3, deferred) with status per item and links to commits
- Repository is now the source of truth on the production host: `~/space-server` is a git working copy tracking `origin/main`, so deploys are `git pull && docker compose up -d`
- `.github/workflows/validate.yml` smoke-checks every compose file's syntax on push

### Changed

- Roundcube webmail now uses STARTTLS to reach mail (`tls://mail`); docker-mailserver's dovecot was rightly rejecting plaintext IMAP
- Mail-server stack aligned on the canonical `space-server_web` docker network (was using a separately created `web` network that survived only via an out-of-band `docker network connect`)
- Roundcube config synced to production state (TLS options that had drifted)
- Prometheus retention set to 30 days; named volume persists across restarts
- Grafana now declares `depends_on: prometheus` so startup order is deterministic
- Traefik dynamic config bound at directory-scope, not file-scope, so future in-place edits don't break the bind mount via inode replacement
- README rewritten with an architecture diagram, production incident write-ups, and the live subdomain inventory

### Removed

- Duplicate Dozzle service definition that lived in both root compose and `dozzle/docker-compose.yml`
- Dead `OVERRIDES_HOSTNAME` / `OVERRIDES_DOMAINNAME` env vars in mail compose (not real docker-mailserver variables; silently ignored)
- `SWARM=1`, `TASKS=1`, `SERVICES=1` from docker-socket-proxy environment — not needed outside Swarm mode

### Security

- **Rotated the Traefik basic-auth admin credential.** The previous apr1 hash had been committed to the public repo for ~3 weeks (the `$$` was Compose env-var escape, so Traefik's file provider read it as a real `$`). New credential is bcrypt and lives only in the production `auth.yml` outside git
- `traefik/dynamic/auth.yml` and `mail-server/docker-mailserver/accounts/*.cf` removed from tracking and added to `.gitignore`; `.example` templates with placeholder values committed in their place
- README's deleted blog post links cleaned up (file was committed, then untracked but locally kept)

## [1.0.0] - 2026-04-23

### Added
- Initial production deployment on Hetzner VPS
- 15+ containerized services with Docker Compose
- Traefik v3.6 reverse proxy with automatic SSL
- Ghost blog with MySQL backend
- Portfolio frontend and API (Laravel)
- Complete mail server with docker-mailserver + Roundcube
- Monitoring stack: Grafana + Prometheus + Uptime Kuma
- Centralized logging with Dozzle
- Automated migration scripts

### Infrastructure
- Server: Hetzner VPS (8GB RAM, Intel Xeon, Ubuntu 24.04)
- Downtime during migration: 12 minutes
- Services migrated: 15+
- SSL certificates: Let's Encrypt via Traefik

[Unreleased]: https://github.com/cativo23/space-server/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/cativo23/space-server/releases/tag/v1.0.0
