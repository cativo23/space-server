# ADR-0002: Adopt observability before scaling features

## Status

accepted (2026-05-14)

## Context

The stack had Prometheus and Grafana installed since the original migration but only scraping Traefik's `/metrics`. There were no host metrics, no container metrics, no alert rules, no notification channel. Effective alerting on a personal server costs around 500 MB of RAM and one afternoon — costs ignored before the stack matured.

The original README joke ("Grafana to know when something breaks before I find out on Twitter") was actually still accurate: outages were detected by external monitoring or browser refresh, not by the monitoring stack we already paid for in memory and configuration.

Adding more user-facing services (portfolio, blog improvements, new sites) without observability compounds the silent-failure surface. A second host or migration further down the roadmap multiplies it.

## Decision

Before any net-new user-facing service or major migration, the stack must have:

1. **Host metrics** — `node_exporter` on the underlying VPS.
2. **Container metrics** — `cAdvisor` (per-container CPU, memory, restart counts).
3. **A real alerting pipeline** — `Alertmanager` with at least five base rules (disk, memory, load, container restart loop, cert expiry).
4. **A notification channel** — Discord webhook via the `alertmanager-discord` adapter sidecar (the Discord URL itself is a gitignored secret).
5. **Provisioned dashboards** — Grafana datasource and dashboards configured via mounted YAML/JSON, not clicked together in the UI. Currently: Node Exporter Full (1860), Traefik Standalone (17346), cAdvisor (14282).
6. **Persistent metric storage** — named volume for Prometheus TSDB, 30-day retention.

External uptime checks remain `Uptime Kuma`'s responsibility; this ADR is about *internal* observability and alerting.

## Alternatives considered

- **Hosted observability (Grafana Cloud, Datadog)** — Free tiers exist but introduce a third-party dependency for the most critical signal we have (whether the server is alive). Rejected on principle for a self-hosted infra project.
- **Just `node_exporter` and Grafana, skip Alertmanager** — Dashboards are passive. Without push notifications the value is much lower at 4am. Rejected.
- **Implement custom alerting via a small script** — Reinventing Alertmanager poorly. Rejected.

## Consequences

### Positive

- Disk, memory, container, and certificate problems generate Discord messages before they cause user-visible outages.
- The provisioned-from-files model means dashboards are reproducible and reviewable in Git.
- Grafana's value is finally justified — it has data sources, dashboards, and a story now.

### Negative

- ~500 MB additional RAM footprint, growing slowly as Prometheus TSDB fills.
- Five new containers to keep up to date (mitigated by pinning + Renovate).
- A failed alertmanager-discord adapter (unmaintained image) silently drops alerts; mitigation is to also configure a secondary external check (Uptime Kuma is already doing that for HTTPS endpoints).

### Follow-ups

- Loki + Promtail for log retention and Grafana-side log/metric correlation.
- `blackbox_exporter` for explicit endpoint probes (or stay with Uptime Kuma).
- Migrate off the unmaintained `benjojo/alertmanager-discord` image to a maintained fork or replace with Alertmanager's native `slack_configs` pointing at Discord's Slack-compat endpoint.
- Renovate or Watchtower for managed image-version bumps.
