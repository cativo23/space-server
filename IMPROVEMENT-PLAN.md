# Space Server — Improvement Plan

> Working document. Updated as items are completed. Started 2026-05-14.

Tracks architecture review findings and the order we tackle them. Findings are referenced by ID (F1, F2, ...) so commits and PRs can point back here.

## Status legend

- `[ ]` not started
- `[~]` in progress / partially applied (e.g. code change committed, awaiting production verification)
- `[x]` done and verified

---

## P0 — Critical bugs / single-source-of-truth

- [x] **F19. Roundcube login failed: plaintext IMAP rejected.** Discovered 2026-05-14 immediately after F18 fix. dovecot's default `disable_plaintext_auth=yes` rejected webmail's plain LOGIN even though both containers shared the docker network — docker-mailserver does not auto-populate `login_trusted_networks`. Switched Roundcube's IMAP/SMTP host references to `tls://mail` (STARTTLS) in both env vars and the inline entrypoint heredoc; internal self-signed cert is accepted because `verify_peer = false` was already set. Verified the STARTTLS handshake works (`openssl s_client -starttls imap` returns `OK Pre-login`).
- [x] **F18. Mail-server network mismatch.** Discovered 2026-05-14 when Traefik recreate broke `mail.cativo.dev`. `mail-server/docker-compose.yml` referenced `web: external: true` (literal network name `web`) while every other stack used the project-prefixed `space-server_web`. Routing held only because Traefik had been manually `docker network connect`ed to both. Fixed by pointing the mail-server `web` reference at the canonical `space-server_web` via `name:` override. The standalone `web` network was orphaned and removed.
- [x] **F17. Rotate exposed Traefik basic-auth credential & gitignore secrets.** Discovered 2026-05-14 while preparing prod for git-init: the apr1 hash in `traefik/dynamic/auth.yml` was committed publicly (the `$$` in the file is Docker Compose env-var escape — Traefik file-provider reads it as a single `$`, so the hash was real and exposed for ~3 weeks). Rotated to bcrypt on polaris2, dropped `auth.yml` + `accounts/*.cf` from git tracking, added `.example` templates, fixed Traefik volume bind to directory (file-bind breaks on `sed -i` inode replacement — we hit it live).
- [x] **F1. Deduplicate Dozzle.** Defined in both `docker-compose.yml` (root) and `dozzle/docker-compose.yml`. Same `container_name: dozzle`; whichever stack starts second silently loses. → Keep `dozzle/` folder (matches per-service pattern used by `mail-server/`, `uptime-kuma/`, `traefik/`); remove duplicate from root.
- [x] **F2. Fix mail hostname env var.** Deployed to `polaris2` (2026-05-14). Verified `postconf myhostname = mail.cativo.dev` before AND after container recreation; `dozzle` migrated to its own compose project. No mail downtime beyond the ~16s recreate window.
- [x] **F3. One source of truth for the whole stack.** Ghost, portfolio, portfolio-api, nightwire-docs, and hello-kitty-landing compose files copied from `~/deploy/` on polaris2 into `deploy/` subdirectories in this repo (2026-05-24). Each sub-stack keeps its own `name:` project, so no containers were renamed and no volumes were disrupted. `.env.example` stubs added for each. Root Compose `include:` deferred: merging included files into the parent project would rename running containers and orphan volumes — safe migration plan needed before wiring that up.

## P1 — Resilience and observability

- [x] **F5. Alerting + Grafana dashboards.** Done 2026-05-14. Added `node_exporter`, `cAdvisor`, `Alertmanager`, and a `benjojo/alertmanager-discord` sidecar that translates AM webhooks → Discord. Prometheus now scrapes 5 targets; 8 alert rules across host (disk, mem, load), containers (restart loop, missing), TLS (cert <14d), and scrape-up. Grafana datasource (uid=prometheus) and 3 dashboards (Node Exporter Full 1860, Traefik 3 17346, cAdvisor 14282) provisioned via mounted files. End-to-end verified: fired test alert via AM API → arrived in `#alerts` Discord channel. `DISCORD_WEBHOOK` secret lives in `~/space-server/.env` on polaris2 (gitignored). Blackbox-exporter deferred — Uptime Kuma already covers external probes.
- [x] **F6. Log retention.** Added Loki 3.3.2 + Promtail 3.3.2 in `loki/docker-compose.yml`. Promtail uses Docker service discovery (docker socket + container log dir) to collect logs from all containers and ship to Loki. 7-day retention. Loki added as Grafana datasource via provisioning. Dozzle remains for live tail.
- [x] **F11. SMTP relay via Resend** (free tier, 3k/mo). Configured 2026-05-14. Domain `cativo.dev` verified at Resend (DKIM `resend._domainkey`, MX/SPF on `send.cativo.dev`, no impact on existing root SPF/DKIM). docker-mailserver `RELAY_*` env vars driven from gitignored `.env` on polaris2; outbound now routes through `smtp.resend.com:587` instead of trying direct port 25.

## P2 — Hardening

- [ ] **F7. Network segmentation.** Single `web` network mixes edge, monitoring, app data. Split into `edge` (Traefik only public-facing), `apps`, `mail`, `monitoring`. Backend DBs (Ghost MySQL, portfolio MySQL/Redis) should never touch `edge`.
- [ ] **F8. DNS-01 challenge.** `traefik.yml` uses `tlsChallenge` — fine for explicit hostnames, blocks wildcards. Switch to `dnsChallenge` with Hetzner DNS provider plugin if we ever want `*.cativo.dev`.
- [x] **F13. Trim `dockerproxy` permissions.** Dropped `SWARM=1`, `TASKS=1`, `SERVICES=1` from the docker-socket-proxy env — not relevant outside Swarm mode. Smaller attack surface for Traefik's docker-provider discovery.
- [x] **F14. Don't hardcode host paths in compose.** `mail-server/docker-compose.yml` referenced `/home/cativo23/space-server/traefik/letsencrypt/acme.json` as a hardcoded default. Removed the `:-` fallback — now requires `TRAEFIK_ACME_PATH` to be set explicitly in `.env`. Added to `.env.example`. Polaris2 `.env` must be updated before next mail-server recreate.

## P3 — Quality of life

- [x] **F21. cAdvisor not exposing per-container labels.** Fixed 2026-05-20. Real root cause was NOT `--docker_only=true` — it was that Docker on polaris2 uses the **containerd-snapshotter** image store (`Storage Driver: overlayfs / driver-type: io.containerd.snapshotter.v1`), not the classic `/var/lib/docker/image/overlay2/` layout. cAdvisor v0.49.1 failed layer-ID lookup on every container, so no per-container metrics were registered (only root cgroup). Fix: bump to `cadvisor:v0.55.1` (better containerd integration) + mount `/run/containerd/containerd.sock:ro` + add `--store_container_labels=true` and `--containerd=/run/containerd/containerd.sock` flags. Verified 20 containers now register with `name`/`image` labels; Grafana dashboard 14282 renders. Captured at `docs/screenshots/grafana-cadvisor.jpg`.
- [x] **F22. Uptime Kuma has no monitors configured.** Fixed 2026-05-20. Wrote `scripts/setup-kuma-monitors.py` (idempotent, env-var-driven) plus a `~/setup-kuma-monitors.sh` helper that bootstraps an isolated venv. Registered 11 HTTP(s) monitors — one per running Traefik router (`cativo.dev`, `blog`, `api`, `mail`, `devi`, `grafana`, `prometheus`, `alertmanager`, `dozzle`, `uptime`, `traefik`). Services behind basic auth accept `401` as "Up" (service responding, just gated). Verified Quick Stats: Up 11 / Down 0. The planned `status.cativo.dev` (per `docs/runbooks/status-page.md`) remains to add once Kuma's status page is enabled. **Lib quirk worth keeping:** `uptime-kuma-api` 1.x doesn't know about Kuma 2.2's NOT NULL `conditions` column — script monkey-patches `_build_monitor_data` to inject `conditions=[]` before send.
- [x] **F9.** Added `depends_on: prometheus` to grafana so startup order is deterministic.
- [x] **F10.** Prometheus retention set to 30d via `--storage.tsdb.retention.time=30d`; persistent volume already in place from F5.
- [x] **F12.** Replace Roundcube inline heredoc entrypoint (`mail-server/docker-compose.yml:79-101`) with the existing `roundcube-*.conf.php` files mounted as volumes. Updated `roundcube-config.inc.php` to use STARTTLS (`tls://` prefix) and ssl verify options matching the working heredoc. Added `include(config.docker.inc.php)` so the real Docker entrypoint does not try to modify the read-only mount. Mounted as `:ro` volume; verified 2026-05-24: `config.inc.php` served from host file, webmail returns HTTP 200.
- [x] **F15.** All image tags pinned to specific versions (prometheus:v3.11.2, grafana:13.0.1, alertmanager:v0.32.1, node-exporter:v1.11.1, dockerproxy:0.4.2, mail:15.1.0, roundcube:1.6.15-apache, dozzle:v10.4.1, uptime-kuma:2.2.1; alertmanager-discord pinned by digest since maintainer doesn't tag). All stacks recreated on polaris2 2026-05-24. Renovate/Watchtower for auto-updates deferred — recorded as follow-up in ADR-0002 and F45.
- [ ] **F16.** SOPS or `age` for encrypted secrets in git (enables real Ansible reproducibility without leaking `.env`).

## Deferred — tackle last

- [ ] **F4. Automated backups.** Deferred 2026-05-14 at Carlos' request — wants to land observability and hardening first. `scripts/` are one-shot migration tools, no recurring backup. When picked up: `restic` (encrypted, dedup'd) → Hetzner Storage Box (~€4/mo). Targets: mail-data, ghost volumes, grafana-data, uptime-kuma-data, portfolio-api MySQL/Redis, cliproxy postgres, traefik/letsencrypt. Daily cron + monthly restore test. **Caveat:** this is still the single biggest catastrophic-loss exposure; don't let it slip forever.

## P4 — Security audit findings (2026-05-24)

- [x] **F23. Grafana admin/admin — false positive.** Opus audit flagged `GF_ADMIN_PASSWORD=admin` in `.env`, but the password was already rotated via Grafana UI post-bootstrap. `GF_ADMIN_PASSWORD` only applies on first container creation; after that Grafana persists it in SQLite. Confirmed: `curl -u admin:admin https://grafana.cativo.dev/api/org` returns 401. `.env` value is now a stale artefact — F16 (SOPS) will clean this up structurally.
- [x] **F24. Port 143 (cleartext IMAP) and 995 (POP3S) published to host, bypassing ufw.** Docker iptables rules override ufw; `ss -tlnp` + external probe confirmed 143 was reachable from the internet despite `ufw deny 143`. Roundcube reaches Dovecot via the internal docker network — no host port needed. Removed `143:143` and `995:995` from `mail-server/docker-compose.yml`. Verified 2026-05-24: mail container HostConfig.PortBindings only shows 25/465/587/993.
- [x] **F26. fail2ban only jailing sshd; IMAP/SMTP brute-force unrestricted.** `ENABLE_FAIL2BAN=1` added to mail-server environment. `cap_add: NET_ADMIN` already present. Deployed with F24 on polaris2 2026-05-24.
- [ ] **F27. `.env` files world-readable (mode 0644) + password reuse across services.** `chmod 600` quick-win applied on polaris2. Structural fix is F16 (SOPS). A shared DB password is reused between portfolio-api and Ghost — rotate them independently.
- [x] **F28. Roundcube webmail has no rate-limit on the public login form.** Added `mail-ratelimit` Traefik middleware (10 req/min avg, burst 20, per source IP) in `traefik/dynamic/middlewares.yml`. Chained before `mail-headers@file` on the webmail router.
- [x] **F29. Pending kernel reboot (30-day uptime, updates installed 2026-05-23).** Rebooted 2026-05-24. Kernel `6.8.0-106` → `6.8.0-117`, `reboot-required` cleared, all 20 containers came back cleanly.
- [x] **F30. 17/21 containers without mem_limit on 8 GB host.** Added limits to dockerproxy (64m), traefik (256m), prometheus (1g), alertmanager (128m), alertmanager-discord (64m), node-exporter (64m), cadvisor (256m), grafana (512m). Verified 2026-05-24: limits confirmed active via `docker inspect`.
- [x] **F31. cAdvisor using 747 MB RAM / 17% CPU.** Root cause: `--housekeeping_interval=10s` + all metric collectors enabled + `--store_container_labels=true` on 21 containers. Changed `housekeeping_interval` to 30s and added `--disable_metrics=disk,diskIO,tcp,udp,percpu,sched,process,hugetlb,referenced_memory,resctrl,cpu_topology,memory_numa`. Verified 2026-05-24: both flags confirmed active in running container args.
- [x] **F32. ~3 GB of unused images + 1 dangling volume.** Pruned 2026-05-24. No dangling volumes remained (cleaned up during container recreates). Removed stale `traefik/whoami:v1.11.0` image (container removed in F37).
- [x] **F34. Healthchecks missing on 10 containers.** Added `healthcheck:` blocks to prometheus, alertmanager, and grafana. Verified 2026-05-24: all three show `(healthy)` in `docker ps`.
- [ ] **F35. Ghost backed by EOL MySQL 5.7** (EOL Oct 2023). Migrate to `mysql:8.0` or `mariadb:10.11`. Requires staging test; plan as a separate phase.
- [x] **F37. `whoami` service no longer needed.** Removed from `docker-compose.yml`. Verified 2026-05-24: no whoami container running on polaris2.
- [x] **F43. Grafana provisioning allows UI deletion of provisioned dashboards.** Changed `disableDeletion: false` → `true` in `grafana/provisioning/dashboards/dashboards.yml`. Verified 2026-05-24: `disableDeletion: true` confirmed in provisioning file on polaris2; Grafana running healthy.

## P5 — Ideas and low-priority (2026-05-24)

- [ ] **F38. alertmanager-discord pinned by digest blocks Renovate** — tag once benjojo releases a versioned tag, or fork into a personal registry.
- [ ] **F33. portfolio-api Docker image is 2.41 GB** — likely single-stage build with dev deps. Audit Dockerfile in source repo.
- [ ] **F36. `~/deploy/` zone has no git repo** — already tracked as F3.
- [ ] **F39. Log persistence (Loki + Promtail)** — already tracked as F6.
- [ ] **F40. Hetzner Cloud Firewall as defense-in-depth** — ufw is bypassed by Docker iptables rules; a Hetzner-level firewall would drop traffic before it hits the host.
- [ ] **F41. `DOCKER-USER` iptables chain** — makes ufw effective for container-published ports without Hetzner Firewall. Lower priority if F40 is adopted.
- [x] **F42. Three untracked files in `mail-server/`** — `dovecot/auth.conf` (not present on polaris2), `roundcube-ssl.inc.php` (stale pre-F19 config, not mounted — gitignored), `README.md` (committed with updated ports table reflecting F24 removal of 143/995).
- [ ] **F44. No probe for auth-required regression on public dashboards** — a Blackbox or synthetic check that verifies Grafana/Prometheus/Alertmanager still require auth would catch future middleware misconfigs automatically.
- [ ] **F45. Self-hosted Renovate** — lightweight cron container for automated image-tag PRs (ties into F15's "Watchtower deferred" note).

## Notes for future sessions

- Carlos has stated: "Docker Compose is enough — no Kubernetes." Don't propose k8s.
- Stated roadmap items already: Ansible reproducibility, dedicated physical server, SMTP relay (done — F11).
- Production host is `polaris2` (Hetzner, 8GB, Ubuntu 24.04). Live mail server.
- `.planning/` directory doesn't exist here; this repo isn't using the GSD workflow.
- F4 (backups) was explicitly deferred to the end by Carlos. Do **not** propose it again as "next" — propose F5/F6/F3/F7 etc. instead.

## Open ADRs to write

1. **ADR-001:** Single repo as source of truth (use Compose `include:`).
2. **ADR-002:** Adopt observability (node_exporter + cAdvisor + Alertmanager) before scaling features.
