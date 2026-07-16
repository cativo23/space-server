# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — self-hosted analytics (Umami) (2026-07-16)

- **Umami analytics stack (F48).** New `umami/` stack: Umami v3 (`umami`, pinned by digest) + a dedicated `postgres:16-alpine` (`umami-db`). Dashboard at `analytics.cativo.dev`, VPN-gated via `internal-only@file` like the other admin UIs (off-VPN → `403`). The DB is on a private `umami-db-net` bridge — **not** on `space-server_web`; the app is on both (web for Traefik + the portfolio same-origin proxy, db-net for Postgres). Postgres data at `/mnt/hdd/umami/pgdata`, UTC. Secrets in `umami/.env` (gitignored). See `docs/runbooks/umami-analytics.md`.
- The public site loads the tracker **same-origin** — the portfolio Nitro server proxies the tracker script + event collector through `cativo.dev` to the internal `umami:3000`, so the tracker host is never public and the site's strict CSP (`connect-src 'self'`) is unchanged. `analytics.cativo.dev` therefore serves only the (VPN-gated) dashboard.

### Added — docs (2026-07-16)

- **ADR-0004 — live infra signal via the docker-socket-proxy.** Records the decision to source the portfolio's public container/stack counts from the existing read-only `dockerproxy` (`/containers/json` list only) rather than Prometheus/cAdvisor, and why the backend (`portfolio-api`) — already co-networked on `space-server_web` — hosts the query. No infra change in this repo; documentation only.

### Added — admin VPN (WireGuard + Traefik allowlist) (2026-06-04)

- **WireGuard admin VPN on polaris2 (F47).** Installed `wireguard`; `wg0` = `10.10.0.1/24` on UDP `51820`, services-only tunnel (no NAT/full-tunnel), `wg-quick@wg0` enabled on boot, ufw opened for `51820/udp`. Keys + `wg0.conf` live in `/etc/wireguard/` (root, 0600) — **never in git**.
- **`internal-only` Traefik middleware** (`traefik/dynamic/middlewares.yml`) — `ipAllowList` with `sourceRange: 10.10.0.0/24`, prepended (first in chain → blocked requests get a clean `403`, no auth-prompt leak) to the `.middlewares=` label of every admin router: traefik-dashboard, prometheus, alertmanager, grafana, uptime, dozzle, mail (webmail). Public visitors now get `403`; the VPN subnet passes through to the service (and its own auth, where present).
- Client reaches the admin UIs by **split-DNS** (`/etc/hosts` → `10.10.0.1`); Traefik routes by Host header so the Let's Encrypt certs stay valid and it sees the real `10.10.0.x` source IP. See `docs/runbooks/admin-vpn.md`.

### Changed

- **Uptime Kuma monitors repointed to internal endpoints (F47).** The 7 monitors for now-VPN-gated routers (mail, grafana, prometheus, alertmanager, dozzle, uptime, traefik) previously hit the public URLs and would have flagged `403`/down. Repointed to `http://<container>:<port>` health endpoints on `space-server_web` (e.g. `grafana:3000/api/health`, `prometheus:9090/-/healthy`, `traefik:8081/ping`) — they now verify real service health instead of the proxy's gate. Supersedes the "accept 401 as Up" approach from F22 for these routers.

### Added — security hardening and resource optimization (2026-05-24)

- `ENABLE_FAIL2BAN=1` on mail container — protects SMTP/IMAP endpoints against brute-force (F26)
- `mem_limit` on all major containers: dockerproxy (64m), traefik (256m), prometheus (1g), alertmanager (128m), alertmanager-discord (64m), node-exporter (64m), cadvisor (256m), grafana (512m) — prevents runaway container from OOM-killing the host (F30)
- Healthchecks on prometheus (`/-/ready`), alertmanager (`/-/ready`), and grafana (`/api/health`) — enables Docker to detect hung processes, not just missing containers (F34)
- `disableDeletion: true` in Grafana dashboard provisioning — prevents accidental UI deletion of provisioned dashboards (F43)

### Changed

- cAdvisor `housekeeping_interval` raised from 10s to 30s; added `--disable_metrics` for unused collectors (disk, diskIO, tcp, udp, percpu, sched, process, hugetlb, etc.) — expected to cut RAM from ~747 MB to ~150 MB (F31)
- Grafana admin password note updated in ARCHITECTURE.md — `GF_ADMIN_PASSWORD` only sets the initial value; subsequent changes are DB-persisted and the `.env` value is a stale artefact (F23)

### Removed

- `whoami` service removed from root `docker-compose.yml` — was only used for Traefik discovery testing; reduces public attack surface (F37)
- Ports `143` (cleartext IMAP) and `995` (POP3S) removed from mail-server host port bindings — Roundcube reaches Dovecot via the internal docker network; Docker was bypassing ufw for these ports (F24)

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
