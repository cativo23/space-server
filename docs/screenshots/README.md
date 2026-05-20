# Screenshots

Visual evidence of the stack in production. The slots below are referenced from the main [README](../../README.md) and [ARCHITECTURE.md](../../ARCHITECTURE.md) — drop the PNGs in here with the exact filenames listed.

| Filename | What to capture | URL |
|---|---|---|
| `grafana-node-exporter.png` | Node Exporter Full dashboard, "Last 6 hours" range, default panels visible | `https://grafana.cativo.dev/d/rYdddlPWk/node-exporter-full` |
| `grafana-traefik.png` | Traefik Official Standalone Dashboard with HTTP Details row expanded (2xx / 5xx / Other codes panels showing real traffic) | `https://grafana.cativo.dev/d/n5bu_kv45/traefik-official-standalone-dashboard` |
| `grafana-cadvisor.png` | cAdvisor dashboard showing per-container CPU + memory | `https://grafana.cativo.dev/d/pMEd7m0Mz/cadvisor-exporter` |
| `discord-alert.png` | A test alert delivered to the `#alerts` Discord channel (fire one with `docker exec alertmanager wget --post-data=…`) | Discord client |
| `traefik-dashboard.png` | Traefik dashboard showing all `Host(...)` routers green | `https://traefik.cativo.dev` |
| `uptime-kuma.png` | Uptime Kuma main monitor view, all endpoints green | `https://uptime.cativo.dev` |

## Capture guidelines

- **Resolution:** 1920×1080 or 1440×900. Anything wider than 1920 wastes space in the README.
- **Theme:** Grafana dark theme (default). Traefik default theme.
- **Crop:** include enough chrome so it's recognizable, but trim the OS window frame.
- **Anonymize:** if any panel happens to surface a real email address or IP that isn't already public, blur it before committing.
- **Format:** PNG. Optimize with `pngquant` or `oxipng` before committing (most of these will be < 200 KB after compression).

```bash
# Quick optimization once you've dropped the PNGs in
oxipng -o 4 docs/screenshots/*.png
```

## Once added

When all six are in place, surface them in the README by appending a "Screenshots" section near the architecture diagram:

```markdown
## Screenshots

| | |
|---|---|
| ![Node Exporter](docs/screenshots/grafana-node-exporter.png) | ![Traefik](docs/screenshots/grafana-traefik.png) |
| ![cAdvisor](docs/screenshots/grafana-cadvisor.png) | ![Discord alert](docs/screenshots/discord-alert.png) |
```
