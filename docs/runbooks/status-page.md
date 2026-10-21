# Runbook: public status page (Uptime Kuma)

Uptime Kuma's built-in status page is the cheapest "health API" we can offer publicly — no new code, no new service, leverages monitors Carlos already configured.

This runbook makes the status page available publicly at **`https://status.cativo.dev/status/public`** (slug `public`). `uptime.cativo.dev` is the admin UI and is VPN-only (`internal-only`, F47), so the public page must be served from the `status.cativo.dev` host, not redirected to it.

> **Live as of 2026-05-20**: the `/status/public` page is configured with three groups (Tools / Mail / Web) and all 11 monitors. Status: All Systems Operational. See `docs/screenshots/status-page.jpg`.

> **Why the UI, not a script?** `uptime-kuma-api` 1.x is too far out of sync with Kuma 2.2's status-page API surface to automate cleanly: the `conditions` column, the `incident` response shape, and `_build_status_page_data`'s kwarg list have all drifted. Each library-side patch surfaces the next mismatch. UI takes ~5 minutes — not worth fighting.

## Prerequisites

- Uptime Kuma already deployed (`uptime-kuma` container)
- At least 3-4 monitors configured (HTTPS check for cativo.dev, blog, mail, etc.)
- Admin access to `https://uptime.cativo.dev`

## Step 1 — create the status page in Uptime Kuma UI

1. Log into `https://uptime.cativo.dev`
2. Top-right menu → **Status Pages** → **New Status Page**
3. **Name:** `Space Server` (visible heading)
4. **Slug:** `public` (the URL will be `/status/public`)
5. **Description:** "Real-time status of the services I self-host. Updates every minute."
6. Click **Save** to create the empty page
7. **Edit** the new page, then drag monitors from the left panel into one or more groups (e.g. *Web*, *Mail*, *Internal*)
8. Optional: upload a logo (use `cativo.dev` favicon)
9. **Save** again

## Step 2 — verify it's public

- Off the VPN, open `https://status.cativo.dev/` in an incognito window (no Kuma session): it should land on `/status/public`
- `https://uptime.cativo.dev/` must still return `403` off the VPN
- All groups + monitors should be visible
- Toggling **Authentication** in page settings can require login if needed

## Step 3 — (optional) alias as `status.cativo.dev`

Two ways:

### Traefik labels on uptime-kuma

`uptime-kuma/docker-compose.yml` defines two routers on `status.cativo.dev`:

- `uptime-status` serves only the paths the page loads, for the `public` slug: `/status/public`, `/api/status-page/public`, `/api/status-page/heartbeat/public`, `/assets/`, `/upload/`, `/icon.svg`. It has no `internal-only`, so it is reachable from the internet. Login, dashboard and socket.io are not matched and stay VPN-only on `uptime.cativo.dev`.
- `uptime-status-root` redirects bare `status.cativo.dev/` to `https://status.cativo.dev/status/public`.

**History:** this used to redirect to `uptime.cativo.dev/status/public`. After F47 gated that host the redirect landed public visitors on a `403` (found 2026-10-20). The redirect has to stay on `status.cativo.dev` itself: a path rewrite on `/` makes Kuma's SPA client-route to `/dashboard` (tried 2026-05-20, reverted).

If you add a second status page with another slug, add its paths to the `uptime-status` rule; the allowlist is per slug on purpose.

`*.cativo.dev` already has a wildcard A record to polaris2, so no DNS step is needed.

## Nightwire skin

The page wears the same design system as cativo.dev. The CSS lives in [`uptime-kuma/status-page.css`](../../uptime-kuma/status-page.css) (tokens copied from `nightwire/nightwire.css`) and is stored in the `custom_css` column of Kuma's `status_page` table. The repo file is the source of truth; the DB is just where Kuma reads it.

Applied 2026-10-20 together with: theme forced to `dark`, logo = the portfolio favicon at `/upload/logo-nightwire.svg` (`/upload/` is one of the paths exposed on `status.cativo.dev`), footer `cativo.dev · built with Nightwire`, and the groups Web / Apps / Identity / Mail / Admin tools (VPN). The monitor for the status page itself is deliberately in no group.

**To change the CSS** (Kuma's UI also has a Custom CSS box under *Edit Status Page*, but it would drift from the repo):

```bash
# 1. back up, then write the repo file into the DB (on polaris2)
docker exec uptime-kuma sqlite3 /app/data/kuma.db ".backup /app/data/kuma.db.bak-$(date +%Y%m%d-%H%M%S)-pre-css"
python3 - <<'PY' | docker exec -i uptime-kuma sqlite3 /app/data/kuma.db
css = open("uptime-kuma/status-page.css").read().replace("'", "''")
print(f"UPDATE status_page SET custom_css='{css}', modified_date=datetime('now') WHERE slug='public';")
PY
# 2. Kuma caches the page in memory for a few minutes; restart to see it now
docker restart uptime-kuma
```

Gotchas: the heartbeat bars are drawn on a `<canvas>` and keep Kuma's own colors; Kuma ships its own sans font on rows, hence the zero-specificity `:where()` rule in the CSS; `@import` of Google Fonts works because the status host sets no CSP (if one is added, allow `fonts.googleapis.com` / `fonts.gstatic.com`).

## Maintenance

- Add new services to monitors as they get deployed
- Status page automatically picks up monitors as you add them to groups
- Slug, name, and groups are editable any time without breaking the URL
