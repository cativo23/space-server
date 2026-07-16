# ADR-0004: Live container/stack counts via the docker-socket-proxy

## Status

accepted (2026-07-16)

## Context

The portfolio's public "SIGNAL · PROOF OF WORK" panel displays a self-hosting
metric — `containers` and `stacks` — under a `LIVE` badge. Those numbers were
hardcoded (`16 containers · 6 stacks`) and had already drifted from reality: this
repo's own README states ~20 containers across ~12 compose projects. A skeptical
reviewer comparing the public site to the public `space-server` README would catch
the discrepancy, which undermines the credibility the panel is meant to project.

We need a live source for the running-container count and the distinct
docker-compose-project (stack) count that `portfolio-api` can read at request time.

Two live sources already exist on the host:

- **cAdvisor via Prometheus** (`monitoring` network, exposed only behind
  `internal-only@file` + `auth@file`).
- **`dockerproxy`** — the read-only `tecnativa/docker-socket-proxy` on the `web`
  (`space-server_web`) network, already fronting `/var/run/docker.sock:ro` for
  Traefik with `CONTAINERS=1`.

## Decision

`portfolio-api` derives the counts by calling `GET dockerproxy:2375/containers/json`
(running containers = list length; stacks = distinct `com.docker.compose.project`
labels) and exposes them at `GET /infra/stats`. The Nuxt BFF's `/api/signal`
aggregates that endpoint alongside its existing GitHub/npm/health calls.

## Alternatives considered

- **Prometheus/cAdvisor** — metrics-only surface (safer), but requires attaching
  `portfolio-api` to the `monitoring` network (an infra change), carries scrape
  lag, and counting via PromQL label-dedup is more brittle than a direct list.
  Rejected: higher operational cost for no accuracy gain.
- **Mount `/var/run/docker.sock` into `portfolio-api`** — rejected: violates
  least-privilege; the socket-proxy exists precisely to avoid raw-socket access.
- **Query dockerproxy from the Nuxt BFF directly** — fewer repos touched (the
  portfolio container is also on `space-server_web`), but embeds docker-API access
  in the public-facing frontend, against the app↔API separation goal. Rejected in
  favour of routing through the backend, mirroring how `/api/signal` already
  fetches `api.cativo.dev`.

## Consequences

### Positive

- **Zero infra change.** `portfolio-api` and `dockerproxy` already share
  `space-server_web`, so `dockerproxy:2375` resolves with no compose edit; the
  API defaults `DOCKER_PROXY_URL` to `http://dockerproxy:2375`.
- The panel's `LIVE` numbers become verifiable and self-correct as the host grows.
- Real-time and exact — no scrape lag, no metric-label guessing.

### Negative

- `CONTAINERS=1` also gates `/containers/{id}/json` (inspect → env vars), so
  `portfolio-api` *gains the capability* to inspect containers. Mitigation: the
  service calls **only** the `/containers/json` list endpoint (no env is ever
  read), the endpoint is read-only and cached, and the network path already
  existed — this is new *usage*, not new *exposure*.
- Adds `dockerproxy` as a soft runtime dependency of `/infra/stats`. Mitigation:
  the service degrades to `null` counts on any failure; the panel renders `…`.

### Follow-ups

- If `portfolio-api` ever needs richer host metrics, revisit the Prometheus path
  (and the `monitoring`-network attach) rather than widening the proxy surface.
