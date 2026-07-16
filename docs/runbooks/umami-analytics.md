# Runbook: Umami analytics (`analytics.cativo.dev`)

Self-hosted, privacy-focused web analytics for `cativo.dev`. Stack lives in `umami/`.

- **Dashboard:** `https://analytics.cativo.dev` — **VPN-gated** (`internal-only@file`), same as the
  other admin UIs. Off-VPN requests get `403`. Add `analytics.cativo.dev` to your client split-DNS
  (`/etc/hosts` → `10.10.0.1`) to reach it; see [admin-vpn.md](./admin-vpn.md).
- **Tracker is NOT public here.** The portfolio site loads the tracker **same-origin** — the
  portfolio Nitro server proxies `/<script>` and the event collector through `cativo.dev` to the
  internal `umami:3000`. This keeps the site's strict CSP (`connect-src 'self'`) intact and dodges
  ad-blockers (requests look first-party). So `analytics.cativo.dev` only ever serves the dashboard.
- **Containers:** `umami` (app, Umami v3, pinned by digest) + `umami-db` (`postgres:16-alpine`).
  The DB is on a private `umami-db-net` bridge — **not** on `space-server_web`. The app is on both
  (web for Traefik + the portfolio proxy; db-net to reach Postgres).
- **Data:** Docker named volume `umami-pgdata` (postgres-alpine is uid 70; a named volume lets
  Docker own it automatically — a root-owned `/mnt/hdd` bind would fail `initdb`). Postgres runs in UTC.

## Secrets

`umami/.env` (gitignored) holds `UMAMI_DB_PASSWORD` and `UMAMI_APP_SECRET`. Generate with
`openssl rand -hex 24` / `openssl rand -hex 32`. Never commit real values.

## Deploy / update

```bash
cd ~/space-server && git pull
cd umami
# first time: cp .env.example .env && fill in secrets  (postgres volume is auto-created)
docker compose up -d
docker compose ps          # both healthy
curl -f http://localhost:3000/api/heartbeat   # from inside the umami netns, or via `docker exec umami`
```

Default first login is `admin` / `umami` — **change it immediately** in the dashboard.

## Verify

- Off-VPN: `curl -so /dev/null -w '%{http_code}' https://analytics.cativo.dev` → `403`.
- On-VPN: dashboard loads (login page).
- Tracker (same-origin, from the public site): `curl -I https://cativo.dev/<tracker-script-path>`
  → `200` with `content-type: application/javascript`; events `POST` to the proxied collector.
