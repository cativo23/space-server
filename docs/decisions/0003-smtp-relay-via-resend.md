# ADR-0003: Route outbound mail through Resend SMTP relay

## Status

accepted (2026-05-14)

## Context

Hetzner blocks outbound TCP port 25 by default for new customers — a long-standing anti-spam measure. Direct delivery from docker-mailserver's Postfix to recipient MX servers is therefore impossible. Inbound mail (port 25 inbound from external MTAs) continues to work because the block is one-directional.

Hetzner does unblock port 25 on request after ~30 days of good account standing, but the request has no guaranteed approval timeline and the IP reputation of a fresh Hetzner VPS is mediocre for direct delivery to Gmail/Microsoft anyway. The existing `mail-server` config had SPF/DKIM/DMARC set up correctly but ran into bounces (visible in the inbox as `MAILER-DAEMON` returned-to-sender messages from April 2026), confirming the block.

The roadmap originally listed "SMTP relay" as a follow-up; this ADR captures the choice and the path.

## Decision

All outbound mail from `docker-mailserver` is routed via the **Resend** SMTP relay (`smtp.resend.com:587`, STARTTLS, free tier with 3,000 messages/month). docker-mailserver configuration:

- `DEFAULT_RELAY_HOST=[smtp.resend.com]:587` — sets Postfix's `relayhost` (brackets prevent MX lookup).
- `RELAY_HOST` / `RELAY_PORT` / `RELAY_USER=resend` / `RELAY_PASSWORD=<resend-api-key>` — populate `/etc/postfix/sasl_passwd` for the matching host. The API key lives in `mail-server/.env` (gitignored); plaintext credentials never enter the repo.

DNS for `cativo.dev` is configured to authorize Resend on a dedicated subdomain (`send.cativo.dev`) so the existing root-domain SPF/DKIM/DMARC records continue to govern direct delivery, leaving room to switch back if Hetzner unblocks port 25.

## Alternatives considered

- **Mailgun / SendGrid / Postmark** — All viable. Resend chosen for the most generous free tier (3 k/mo vs Mailgun's 100/day after trial), modern API, and EU-friendly compliance.
- **AWS SES** — Cheapest at scale (~$0.10 per 1k) but requires sandbox-exit request and more DNS work. Reconsider only if volume goes above Resend's free tier.
- **Wait for Hetzner unblock** — Even if approved, IP reputation is still a fresh Hetzner /24, so deliverability would be worse than going through a provider with dedicated warm IPs. Rejected.
- **MXroute / generic flat-rate SMTP** — Cheaper at high volume but more setup for unclear benefit at our volume.
- **Switch VPS providers (OVH, Scaleway)** — Heavy lift for a port problem.

## Consequences

### Positive

- Outbound mail works reliably to Gmail, Outlook, Apple Mail, etc., backed by Resend's warm IP pool.
- DKIM signatures from Resend supplement the existing local DKIM; recipients see two passing signatures.
- The `mail-server` stack stays largely unchanged — relay is configured via env vars, not code.
- Resend's dashboard provides per-message tracking IDs and bounce/complaint visibility we wouldn't have with direct delivery.

### Negative

- A new external dependency. If Resend goes down, outbound mail goes down. Mitigation: a secondary relay (e.g., Mailgun free tier) can be configured by adding a second entry to `/tmp/docker-mailserver/postfix-sasl-password.cf` and a `postfix-relaymap.cf` rule.
- Volume cap at 3 k/mo on free tier. Personal use is nowhere near this, but a runaway alert loop or spam test could spike it.
- The Resend API key is a long-lived secret in `.env`. Rotation is straightforward but operationally a future chore.

### Follow-ups

- Add a Prometheus alert when Resend's daily volume approaches the free-tier cap (would need Resend's API + a small exporter).
- Document the rotation procedure (delete old key in Resend dashboard → update `mail-server/.env` → `docker compose up -d mail`) in a runbook.
- Reconsider this ADR if outbound volume grows past free tier or Hetzner unblocks port 25 with a clean IP reputation.
