# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — disk hygiene: image retention, log caps, fill-rate alert (2026-10-22)

- **Image retention** (PR #32): `scripts/docker-retention.sh` with `systemd/docker-retention.{service,timer}` removes superseded image tags, keeping the last 3 per repository and never an image a container uses. The timer runs in dry-run mode; `--apply` is a later, separate change. The old tags piled up because deploys only ran `docker image prune -f`.
- **`HostDiskFillingFast`** (PR #32): slope alert for a disk that will fill soon even though it is under the 85% threshold.
- **Container log rotation** (PR #33, #34): `docker/daemon.json` caps every new container's `json-file` log at 10 MB × 5 and enables `live-restore`, so the daemon restart that applies it does not stop containers. `scripts/check-daemon-json.sh` validates the values, which `dockerd --validate` does not, and exits 70 when `jq` is missing. Runbook: `docs/runbooks/container-log-rotation.md`. Existing containers keep their old log config until recreated.
- Effect on the host: root disk 90% → 64% after the old images and the build cache were removed; three retired projects were removed from the server.

### Changed — monitoring costs less and the disk alerts stack correctly (2026-10-22)

- **cAdvisor no longer exports `advtcp`** (PR #35): 61% of the samples of every scrape, read by no dashboard or alert. With the 30 s interval and 20 s timeout (PR #36) the scrape went from 3.2 s to 1.4 s and from 7,620 to 2,967 samples.
- **node-exporter healthcheck probes `/`** (PR #37) instead of `/metrics --spider`, which logged a broken-pipe error on every probe.
- **`HostDiskSpaceCritical` inhibits `HostDiskSpaceLow` and `HostDiskFillingFast`** (PR #38) by explicit alert name, equal on instance and mountpoint. `tests/alertmanager-inhibit.bats` runs the pinned Alertmanager to prove it, in the new `alertmanager inhibit rule` CI job.

### Changed — the blog moves to Ghost 6.72 and MySQL 8.4 LTS (2026-10-21)

- **`deploy/ghost` now runs `ghost:6.72.0-alpine` and `mysql:8.4.11`**, both pinned by digest (F15, F35). Ghost 5 (EOL Jan 2026) and MySQL 8.0 (EOL 2026-04-30) are gone from production. Cutover took 79 s: 75 tables, 1410 rows and 73 foreign keys identical, 361 → 506 migrations, 22 posts served, 89 content files with matching checksums.
- **New volumes** `ghost-blog-prod_ghost-content-v6` and `ghost-blog-prod_db-data-84`. The old `ghost-content` and `db-data` volumes are untouched and not declared in the compose file, so `down -v` cannot delete them. The `--default-authentication-plugin` flag is removed (mysqld 8.4 refuses it).
- **Required collation step:** Ghost 6 creates tables with `default character set utf8mb4`, which MySQL resolves to `utf8mb4_0900_ai_ci`; that cannot be a foreign key against the `utf8mb4_general_ci` tables of a Ghost 5 database (errno 3780 in `add-gifts-table`, reproduced on MySQL 8.0.46 too). Setting the database default does not help. The restored database was converted with `ALTER TABLE ... CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci` before Ghost started.
- **Rollback window:** tag `ghost-pre-b`, the old volumes and `~/backups/ghost-cutover-20261021T034320Z` (final dump, cold copy of the old data dir, row counts). Old volumes are removed on 2026-10-28 after a separate approval; no `image prune -a` or `volume prune` until then.

### Fixed — Ghost 6 admin could not show its login (2026-10-21)

- `custom-errors` replaced the 403 JSON of `/ghost/api/admin/users/me/` with the styled HTML page, so the admin app stopped on "Something went wrong while loading users". A separate router for `Host(blog.cativo.dev) && PathPrefix(/ghost)` (priority 100) has no error middleware; public pages keep the styled errors.

### Changed — images pinned, nginx off the EOL line (2026-10-21)

- ghost, mysql, bugsink and its postgres pinned to the digests running at the time (PR #28); the error-pages nginx moved from the EOL 1.27 line to `1.30.6-alpine` by digest (PR #29).
- The `Deploy` workflow of `cativo23/ghost-blog` was disabled; it would have run `compose down/up` against this same project on a release.

### Fixed — public status page was a 403 (2026-10-20)

- **`status.cativo.dev` now serves the status page itself** instead of redirecting to `uptime.cativo.dev`, which has been behind `internal-only` since F47. Only the `public` slug's paths are exposed (`/status/public`, its API, `/assets/`, `/upload/`, `/icon.svg`); login, dashboard and socket.io stay VPN-only. See F51 and `docs/runbooks/status-page.md`.

### Added — Uptime Kuma coverage and a Nightwire status page (2026-10-20)

- **Monitors 11 → 21** (F52): the status page, tcgvault, clarify, nova-id `app`/`auth`/`admin`, tcg, binder, nightwire and TCP checks on `mail.cativo.dev:587`/`:993`. `devi.cativo.dev` was dropped. `scripts/setup-kuma-monitors.py` gained a `TCP_MONITORS` table.
- **Nightwire skin** for the public page (`uptime-kuma/status-page.css`), new favicon, generic description, groups Web / Apps / Identity / Mail. The admin-tool monitors keep running and alerting but are not published (F53).

### Changed — host maintenance (2026-10-20)

- **polaris2 rebooted** onto kernel 6.8.0-147 after a reboot pending since 2026-10-14, and `mail-server` recreated so Roundcube runs the pinned `1.6.19` instead of `1.6.15` (F54).
- **README and `IMPROVEMENT-PLAN.md` re-audited against production.** F7, F15, F30, F34 and F40 are back to in-progress; new items F56–F59 opened.

### Removed — Umami analytics (2026-10-20)

- **The `umami/` stack (F48) is gone.** Umami had been stopped to free resources and the portfolio no longer loads its tracker (portfolio 1.23.0), so the stack, its `.env.example` and the `umami-analytics` runbook are deleted, along with the passing mentions in the admin-VPN runbook, the paused-services fallback comment and the bugsink compose comments.
  - **Done on polaris2:** `docker compose down` in `umami/`, `docker volume rm umami_umami-pgdata` (no backup kept — the data was barely used) and the Umami image removed. No Uptime-Kuma monitor existed for it. `analytics.cativo.dev` is covered by the wildcard record, so DNS needs no change; with no router left it falls through to the `paused-fallback` error page.

### Added — HTTP/3 on Traefik (2026-10-20)

- `websecure` now serves HTTP/3 (QUIC on UDP 443); Traefik advertises it with `Alt-Svc`, and clients without UDP 443 keep using HTTP/2. The `traefik` service publishes `443:443/udp`; the Hetzner firewall runbook and `setup-polaris2.sh` list UDP 443.
  - **Deploy:** Docker publishes the port past ufw, so the gate that matters is the Hetzner Cloud Firewall — if it is applied to polaris2, add an inbound UDP 443 rule there first (the `ufw allow 443/udp` in the setup script is hygiene only). Then `git pull && docker compose up -d traefik` (static config: Traefik restarts, a few seconds of downtime for every site; `acme.json` persists).
  - **Verify:** `docker port traefik` lists `443/udp`; `curl -sI https://tcgvault.cativo.dev | grep -i alt-svc` shows `h3`; `curl --http3-only -sI https://tcgvault.cativo.dev` succeeds from outside; from the VPN, `curl --http3-only -sI https://traefik.cativo.dev` answers 401/200, not 403 (the `internal-only` allowlist still sees the real client IP over QUIC); `docker logs traefik` shows no errors; watch `docker stats traefik` against its 256m limit.
  - **Rollback:** remove the `http3` block and the `443/udp` port, `docker compose up -d traefik`; clients that cached `Alt-Svc` fall back to TCP after one failed UDP attempt.

### Added — self-hosted analytics (Umami) (2026-07-16)

- **Umami analytics stack (F48).** New `umami/` stack: Umami v3 (`umami`, pinned by digest) + a dedicated `postgres:16-alpine` (`umami-db`). Dashboard at `analytics.cativo.dev`, VPN-gated via `internal-only@file` like the other admin UIs (off-VPN → `403`). The DB is on a private `umami-db-net` bridge — **not** on `space-server_web`; the app is on both (web for Traefik + the portfolio same-origin proxy, db-net for Postgres). Postgres data on the Docker named volume `umami-pgdata`, UTC. Secrets in `umami/.env` (gitignored). See `docs/runbooks/umami-analytics.md`.
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
