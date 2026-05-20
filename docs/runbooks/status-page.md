# Runbook: public status page (Uptime Kuma)

Uptime Kuma's built-in status page is the cheapest "health API" we can offer publicly — no new code, no new service, leverages monitors Carlos already configured.

This runbook makes the status page available at **`https://uptime.cativo.dev/status/public`** (or a custom slug). Optional Cloudflare CNAME hop to alias it as `status.cativo.dev`.

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

- Open `https://uptime.cativo.dev/status/public` in an incognito window (no Kuma session)
- All groups + monitors should be visible
- Toggling **Authentication** in page settings can require login if needed

## Step 3 — (optional) alias as `status.cativo.dev`

Two ways:

### Easy: Cloudflare page rule / redirect

In Cloudflare → `cativo.dev` zone → **Page Rules**:

- If URL matches `status.cativo.dev/*`
- Forwarding URL → 301 → `https://uptime.cativo.dev/status/public`

### Cleaner: Traefik label on uptime-kuma

Add a second rule to `uptime-kuma/docker-compose.yml`:

```yaml
labels:
  # existing labels stay...
  - "traefik.http.routers.uptime-status.rule=Host(`status.cativo.dev`)"
  - "traefik.http.routers.uptime-status.entrypoints=websecure"
  - "traefik.http.routers.uptime-status.tls.certresolver=letsencryptresolver"
  - "traefik.http.routers.uptime-status.middlewares=status-redirect,security-headers@file"
  - "traefik.http.middlewares.status-redirect.redirectregex.regex=^https?://status\\.cativo\\.dev/?$"
  - "traefik.http.middlewares.status-redirect.redirectregex.replacement=https://uptime.cativo.dev/status/public"
```

Then in Cloudflare add a CNAME or A record pointing `status.cativo.dev` → `cativo.dev` (DNS only).

## Step 4 — surface in README

Once the status page is live, replace the `Uptime Kuma` row in the README's "Public subdomains" table with two rows:

| `status.cativo.dev` | Public uptime status page |
| `uptime.cativo.dev` | Uptime Kuma admin (auth) |

## Maintenance

- Add new services to monitors as they get deployed
- Status page automatically picks up monitors as you add them to groups
- Slug, name, and groups are editable any time without breaking the URL
