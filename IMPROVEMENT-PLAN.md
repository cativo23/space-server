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
- [ ] **F3. One source of truth for the whole stack.** Ghost, portfolio, portfolio-api, cliproxyapi live outside this repo. Reproducibility (Ansible goal) is impossible until everything is declared somewhere committed. Options: (a) Compose v2.20+ `include:` directive in a root `compose.yaml`, (b) git submodules, (c) consolidate into this repo. Recommend (a).

## P1 — Resilience and observability

- [ ] **F4. Automated backups.** `scripts/` are one-shot migration tools, no recurring backup. Pick `restic` (encrypted, dedup'd, easy) → Hetzner Storage Box (~€4/mo). Backup: mail-data, ghost volumes, grafana-data, uptime-kuma-data, portfolio-api MySQL/Redis, cliproxy postgres, traefik/letsencrypt. Daily cron + monthly restore test.
- [ ] **F5. Alerting.** Prometheus only scrapes Traefik. Add: `node_exporter` (host), `cAdvisor` (containers), `blackbox_exporter` (external uptime), `Alertmanager`. Minimum 5 rules: disk >85%, cert <14d, container restart loop, host load >2, mail queue >50.
- [ ] **F6. Log retention.** Dozzle is a viewer; logs vanish on container restart. Add Loki + Promtail (or `loki-docker-driver` plugin). Plug into existing Grafana.
- [ ] **F11. SMTP relay** (already on Carlos' roadmap). Hetzner blocks outbound :25, so outbound mail is broken until we relay through Mailgun / Postmark / AWS SES.

## P2 — Hardening

- [ ] **F7. Network segmentation.** Single `web` network mixes edge, monitoring, app data. Split into `edge` (Traefik only public-facing), `apps`, `mail`, `monitoring`. Backend DBs (Ghost MySQL, portfolio MySQL/Redis) should never touch `edge`.
- [ ] **F8. DNS-01 challenge.** `traefik.yml` uses `tlsChallenge` — fine for explicit hostnames, blocks wildcards. Switch to `dnsChallenge` with Hetzner DNS provider plugin if we ever want `*.cativo.dev`.
- [ ] **F13. Trim `dockerproxy` permissions.** Drop `SWARM=1`, `TASKS=1`, `SERVICES=1` (not used). Smaller attack surface.
- [ ] **F14. Don't hardcode host paths in compose.** `mail-server/docker-compose.yml:22` references `/home/cativo23/space-server/traefik/letsencrypt/acme.json`. Breaks if Ansible deploys under a different user. Use a `${TRAEFIK_ACME_PATH}` env var with no hardcoded default.

## P3 — Quality of life

- [ ] **F9.** Add `depends_on: prometheus` to grafana.
- [ ] **F10.** Set Prometheus retention (`--storage.tsdb.retention.time=30d`) and a named volume.
- [ ] **F12.** Replace Roundcube inline heredoc entrypoint (`mail-server/docker-compose.yml:79-101`) with the existing `roundcube-*.conf.php` files mounted as volumes.
- [ ] **F15.** Pin all image tags (no `:latest`). Add Renovate or Watchtower for managed updates.
- [ ] **F16.** SOPS or `age` for encrypted secrets in git (enables real Ansible reproducibility without leaking `.env`).

## Notes for future sessions

- Carlos has stated: "Docker Compose is enough — no Kubernetes." Don't propose k8s.
- Stated roadmap items already: Ansible reproducibility, dedicated physical server, SMTP relay.
- Production host is `polaris2` (Hetzner, 8GB, Ubuntu 24.04). Live mail server — F2 needs prod verification.
- `.planning/` directory doesn't exist here; this repo isn't using the GSD workflow.

## Open ADRs to write

1. **ADR-001:** Single repo as source of truth (use Compose `include:`).
2. **ADR-002:** Adopt observability (node_exporter + cAdvisor + Alertmanager) before scaling features.
