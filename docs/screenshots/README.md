# Screenshots

Visual evidence of the stack in production. Captures referenced from the main [README](../../README.md) and [ARCHITECTURE.md](../../ARCHITECTURE.md).

## Captured

| Filename | What it shows | Source |
|---|---|---|
| `grafana-node-exporter.jpg` | Node Exporter Full dashboard — live CPU 6%, RAM 29.1%, disk 36.4%, swap 0.8%, uptime 3.8 weeks, plus the CPU Basic / Memory Basic time-series for the past 3 hours | `https://grafana.cativo.dev/d/rYdddlPWk/node-exporter-full` |
| `grafana-traefik.jpg` | Traefik Standalone dashboard — HTTP code distribution (GET[200] 61%, GET[404] 16%, GET[302] 12%, …), requests per entrypoint, Apdex per method, top slow services, most-requested services | `https://grafana.cativo.dev/d/n5bu_kv45/traefik-official-standalone-dashboard` |
| `uptime-kuma.jpg` | Uptime Kuma dashboard — 11 monitors registered (one per public subdomain), Quick Stats: Up 11 / Down 0. Event log shows mixed `200 OK` and `401 Unauthorized` heartbeats (auth-gated services counted as Up since 401 means "service responding"). Captured after F22 fix. | `https://uptime.cativo.dev/dashboard` |
| `grafana-cadvisor.jpg` | cAdvisor exporter dashboard — per-container CPU% time-series with legend (alertmanager 0.0983%, cadvisor 7.30%, ghost-blog-prod-db-1 0.595%, …), Memory Usage and Memory Cached panels. Captured after F21 fix (cAdvisor bumped to v0.55.1 for containerd-snapshotter support). | `https://grafana.cativo.dev/d/pMEd7m0Mz/cadvisor-exporter` |
| `status-page.jpg` | Public Uptime Kuma status page — "All Systems Operational" headline, 11 monitors grouped into Tools / Mail / Web, all 100% green. Configured via the Kuma UI per `docs/runbooks/status-page.md` Step 1. | `https://uptime.cativo.dev/status/public` |

## Pending

| Filename | Why not captured | Next step |
|---|---|---|
| `traefik-dashboard.jpg` | Traefik UI loads but its XHR API calls reject URL-embedded basic auth (Chrome doesn't propagate creds from URL into fetch headers) | Capture from a browser session with the credential already in the Chrome credential manager |
| `discord-alert.jpg` | Discord client only — not accessible from the MCP browser | Capture from your Discord client after firing a test alert with `docker exec alertmanager wget --post-data='[{"labels":{"alertname":"TestF5","severity":"warning","instance":"polaris2"}}]' --header=Content-Type:application/json http://localhost:9093/api/v2/alerts` |

## Capture guidelines

- **Resolution:** captured at 1346×591 (MCP browser viewport). For higher-resolution captures use a real browser at 1920×1080+.
- **Format:** JPG for the captured set (matches what the MCP screenshot tool produces). PNG is also fine.
- **Anonymize:** if any panel happens to surface a real email address or IP that isn't already public, blur it before committing.
- **Optimize:** `oxipng -o 4 docs/screenshots/*.png` if you swap to PNG.

## Once added

When all six are in place, surface them in the README by appending a "Screenshots" section near the architecture diagram:

```markdown
## Screenshots

| | |
|---|---|
| ![Node Exporter](docs/screenshots/grafana-node-exporter.jpg) | ![Traefik](docs/screenshots/grafana-traefik.jpg) |
| ![cAdvisor](docs/screenshots/grafana-cadvisor.png) | ![Discord alert](docs/screenshots/discord-alert.png) |
```
