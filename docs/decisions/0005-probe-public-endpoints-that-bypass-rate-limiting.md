# ADR-0005: Probe public endpoints that bypass rate limiting

## Status

accepted (2026-09-02)

## Context

On 2026-09-02 at 06:23 UTC, Uptime Kuma paged Discord that `api.cativo.dev` was
down. It was not. The container had been `Up (healthy)` for five weeks and the
public endpoint answered `200` throughout.

Two facts combine to produce the false alert:

**1. Kuma's probes hairpin.** The four monitors that target public hostnames
(`cativo.dev`, `blog.cativo.dev`, `api.cativo.dev`, `devi.cativo.dev`) leave the
host, hit its own public IP, and re-enter through Docker's NAT. Traefik therefore
sees them arriving from `172.19.0.1` — the `space-server_web` gateway — not from
a real client address. In the Traefik access log, `172.19.0.1` is the single
largest client by a wide margin: 276,244 of 1,061,718 logged requests, of which
273,969 are `GET /`. That count matches four monitors at one request per minute
over the retention window almost exactly.

**2. `portfolio-api` trusts the proxy and buckets by that address.** The app sets
`trust proxy` (correct — real browser traffic does get real client IPs) and
applies a global `ThrottlerGuard` at `THROTTLE_LIMIT=10` per `THROTTLE_TTL=60`s.
Every hairpinned request therefore shares **one** 10-request-per-minute bucket,
regardless of which of the four monitors sent it. Measured directly: 15 rapid
requests to `/` return `200` ten times, then `429` five times.

The monitor for `api.cativo.dev` was probing `GET /` — a route the API does not
define, which is why its accepted-status list had `404` bolted on. That path is
subject to the global throttler. So when the shared gateway bucket overflowed,
the monitor got `429`, which was not in its accepted list, and Kuma paged.

The blast radius is narrow but the signal quality was terrible:

- `api.cativo.dev` has **8** `important` DOWN events, from 2026-06-07 to
  2026-09-02. **All 8** are `Request failed with status code 429`. It has never
  once recorded a real outage — a 100% false-positive rate, and the noisiest
  monitor on the stack (the next is `grafana.cativo.dev` at 4).
- Only 24 of the API's 1,862 throttler exceptions originate from `172.19.0.1`.
  The other ~1,838 are external scrapers being rate-limited correctly, which is
  the throttler working as designed.

So this is an **alerting-fidelity problem, not a capacity problem**. Nothing was
ever unavailable to users, and the rate limiter needs no loosening.

Crucially, `GET /health` is **already exempt** from the throttler upstream: 15
rapid requests return `200` fifteen times, both from inside the network and over
the public hostname. It also returns a far richer signal than the `404` the
monitor was accepting — database, redis, memory, and disk component status.

## Decision

Point the `api.cativo.dev` monitor at `https://api.cativo.dev/health` and tighten
its accepted statuses to `200-299`. Keep the probe on the **public hostname** so
it continues to exercise DNS, TLS, and Traefik routing end to end.

The other three public monitors are left on their public hostnames unchanged:
`cativo.dev` (Nuxt) and `blog.cativo.dev` (Ghost) have no application rate
limiter, so their hairpinned probes are harmless — verified with 12 rapid
requests each, all `200`.

## Alternatives considered

- **Repoint all four public monitors at internal container URLs**
  (`http://portfolio-api-deploy-api-1:3000/...`). This removes the hairpin at the
  root and follows the precedent set in F47 for the VPN-gated admin routers.
  Rejected for the *public* services: it trades a rare false positive for a
  permanent blind spot. An internal probe cannot see an expired certificate, a
  broken Traefik router, or a DNS failure — precisely the faults that actually
  take the site down for real users. That trade is right for an admin UI whose
  public path is deliberately `403`; it is wrong for the product surface. The
  premise was also over-broad: only one of the four monitors was ever affected.
- **Change `portfolio-api` to skip the throttler for health checks or for the
  gateway IP.** Unnecessary — measurement shows `/health` is already exempt, so
  this is a redeploy of a separate repository for no behavioural gain.
- **Fix the hairpin at the Docker/host NAT layer** so probes keep their real
  source address. Disproportionate: host-wide packet-path surgery affecting every
  container, to remove eight false alerts in three months.
- **Add `429` to the monitor's accepted statuses**, reusing the `401` precedent
  already codified for basic-auth-gated services ("the service IS up, just
  gated"). Defensible, and it would have silenced the page. Rejected because it
  keeps the probe pointed at a non-existent route, so a genuinely throttled API
  would read as healthy. Probing an endpoint that is *designed* not to be
  throttled is the stronger fix.

## Consequences

### Positive

- Removes the only recurring false-positive alert on the stack, protecting the
  Discord channel's signal-to-noise ratio — the reason F5/F46 exist at all.
- Upgrades the API's health signal from "some route returned 404" to an actual
  dependency check covering database, redis, memory, and disk.
- Full public-path coverage is retained: DNS, TLS expiry, and Traefik routing are
  still exercised on every beat.
- No application redeploy and no host networking change. The rate limiter keeps
  doing its job against the external scrapers that make up ~99% of its trips.

### Negative

- The probe no longer detects the API being rate-limited into uselessness for
  anonymous clients, since `/health` is exempt by design. Accepted: Kuma answers
  "is it reachable", and Prometheus/Grafana own "is it healthy under load". That
  separation is the intent of ADR-0002.
- The hairpin itself remains. Any *other* internal caller that reaches the API by
  its public hostname still shares the `172.19.0.1` throttle bucket. This is
  currently near-zero — the portfolio frontend already calls the API internally
  via `NUXT_API_BASE_URL=http://portfolio-api-deploy-api-1:3000` — but it is a
  trap for future services.

### Follow-ups

- **Internal callers must use internal URLs.** New services on `space-server_web`
  that talk to another service on the host should address it by container name,
  never by its public hostname, to avoid re-entering this bucket.
- `GET /health` is publicly reachable and discloses component-level status
  (database/redis/disk up-down). Low severity, but worth restricting to the
  internal network or trimming the public response body.
- The `172.19.0.1` collapse means `portfolio-api` cannot rate-limit hairpinned
  callers apart from one another. If internal-to-public traffic ever grows, prefer
  fixing the caller over widening the limit.
