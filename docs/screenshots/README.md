# Screenshots

Visual evidence of the stack in production. Captures referenced from the main [README](../../README.md) and [ARCHITECTURE.md](../../ARCHITECTURE.md).

## Captured

| Filename | What it shows | Source |
|---|---|---|
| `grafana-node-exporter.jpg` | Node Exporter Full dashboard — live CPU 6%, RAM 29.1%, disk 36.4%, swap 0.8%, uptime 3.8 weeks, plus the CPU Basic / Memory Basic time-series for the past 3 hours | `https://grafana.cativo.dev/d/rYdddlPWk/node-exporter-full` |
| `grafana-traefik.jpg` | Traefik Standalone dashboard — HTTP code distribution (GET[200] 61%, GET[404] 16%, GET[302] 12%, …), requests per entrypoint, Apdex per method, top slow services, most-requested services | `https://grafana.cativo.dev/d/n5bu_kv45/traefik-official-standalone-dashboard` |
| `uptime-kuma.jpg` | Uptime Kuma dashboard — note: empty Quick Stats here; monitors still pending (TODO) | `https://uptime.cativo.dev` |

## Pending

| Filename | Why not captured | Next step |
|---|---|---|
| `grafana-cadvisor.jpg` | Dashboard renders "No data" because our cAdvisor only emits `id`/`instance`/`cpu`/`job` labels (missing `name`/`image`) — likely cgroup v2 + `--docker_only=true` interaction. Tracked as F21 in `IMPROVEMENT-PLAN.md` | Fix cAdvisor flags, then re-capture |
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
