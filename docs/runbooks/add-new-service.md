# Runbook: add a new service behind Traefik

End-to-end checklist for exposing a new container at `<something>.cativo.dev` with auto-TLS and the right network attachments.

## 1. Pick the topology

Decide ahead of time:

- **Subdomain:** `<thing>.cativo.dev` (Traefik's docker-provider matches `Host(...)` rules)
- **Internal port:** what port the container exposes inside its network (e.g. `:3000`, `:80`)
- **Public or auth-gated?** If internal (Grafana-like), add `auth@file` middleware
- **Has a backend DB?** Create a second compose-internal network so the DB isn't on `space-server_web`

## 2. Compose snippet

Drop this in your stack's compose file:

```yaml
services:
  thingy:
    image: vendor/thingy:1.2.3       # ALWAYS pinned, never :latest
    container_name: thingy
    restart: unless-stopped
    environment:
      - SECRET=${THINGY_SECRET}      # gitignored .env, never inline
    volumes:
      - thingy-data:/data            # named volume, listed in volumes:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.thingy.rule=Host(`thingy.cativo.dev`)"
      - "traefik.http.routers.thingy.entrypoints=websecure"
      - "traefik.http.routers.thingy.tls.certresolver=letsencryptresolver"
      - "traefik.http.routers.thingy.middlewares=security-headers@file"   # add auth@file too for internal
      - "traefik.http.services.thingy.loadbalancer.server.port=3000"
    networks:
      - space-server_web             # web exposure
      - thingy-internal              # only if there's a DB
```

Append the network and volume blocks:

```yaml
volumes:
  thingy-data:

networks:
  space-server_web:
    external: true
  thingy-internal:
    driver: bridge
```

## 3. DNS

In Cloudflare → `cativo.dev` zone:

- Add an **A record**: `thingy` → `167.235.52.161` (polaris2 IP)
- Proxy status: **DNS only** (Cloudflare proxy would interfere with Let's Encrypt and may strip mail-relevant headers)
- TTL: Auto

## 4. Deploy

```bash
# Local
git add <changes>
git commit -m "feat(thingy): deploy at thingy.cativo.dev"
git push origin <branch>      # CI validates compose syntax

# Once merged to main
ssh polaris2 'cd ~/space-server && git pull && docker compose up -d'
```

## 5. Verify

```bash
# Cert acquired
curl -sI https://thingy.cativo.dev | head -3

# Traefik knows the router
curl -sS -u "admin:$TRAEFIK_PASS" https://traefik.cativo.dev/api/http/routers | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print([r['name'] for r in d if 'thingy' in r['name']])"

# Prometheus picks up cAdvisor metrics for the new container automatically (no scrape config edit needed)
```

## 6. (Optional) add to monitoring

- **Uptime Kuma:** add an HTTP(s) monitor for `https://thingy.cativo.dev`
- **Grafana:** if the service exposes Prometheus metrics, add a scrape job in `prometheus/prometheus.yml`
- **Alert rules:** consider per-service rules in `prometheus/alert_rules.yml` (e.g. error rate, latency)

## Anti-patterns to avoid

- ❌ `image: vendor/thingy:latest` — kills reproducibility (see ADR-0001's follow-ups for Renovate)
- ❌ Hardcoding secrets in environment block — use `${VAR}` and document the var in `.env.example`
- ❌ Mounting the DB on `space-server_web` — internal-only network or nothing
- ❌ Cloudflare proxy turned on — breaks ACME challenge and may rewrite headers
- ❌ Skipping the security-headers middleware — HSTS / CSP / X-Frame-Options should be on by default
