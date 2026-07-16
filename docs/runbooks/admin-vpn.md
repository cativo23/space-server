# Runbook: admin VPN (WireGuard) for internal UIs

The admin/observability UIs are **not on the public internet**. They are gated by a Traefik
`ipAllowList` middleware to the WireGuard subnet `10.10.0.0/24`. Off-VPN requests get `403`.

- **Server:** `wg0` = `10.10.0.1/24`, UDP `51820`, on polaris2. Services-only tunnel (no
  full-tunnel / no NAT). `wg-quick@wg0` is enabled (survives reboot). ufw allows `51820/udp`.
- **Gated routers:** `traefik-dashboard`, `prometheus`, `alertmanager`, `grafana`, `uptime`,
  `dozzle`, `mail` (webmail), `umami` (analytics). **Not gated:** `cativo.dev`, `api`, `blog`,
  `devi`, `status`.
- **Not affected:** mail transport (SMTP/IMAP `25/465/587/993`) stays public — only the
  webmail HTTP UI is behind the VPN.
- **Recovery:** SSH (`cativo23@167.235.52.161:52222`) is out-of-band and never gated.
- Keys live only in `/etc/wireguard/` on the box (root, `0600`) — **never commit them**.

---

## 1. Connect a client

You need two things: the WireGuard config and a split-DNS entry.

### a) WireGuard config

Save as `/etc/wireguard/wg0.conf` on the client:

```ini
[Interface]
PrivateKey = <client-private-key>
Address = 10.10.0.<N>/24

[Peer]
PublicKey = <server-public-key>        # `sudo wg show wg0` on polaris2
Endpoint = 167.235.52.161:51820
AllowedIPs = 10.10.0.0/24               # services-only; do NOT add the public IP (routing loop)
PersistentKeepalive = 25
```

### b) Split-DNS (`/etc/hosts` on the client)

```
10.10.0.1 traefik.cativo.dev grafana.cativo.dev prometheus.cativo.dev alertmanager.cativo.dev dozzle.cativo.dev uptime.cativo.dev mail.cativo.dev
```

Traefik routes by `Host` header, so pointing the names at `10.10.0.1` keeps the Let's Encrypt
certs valid and the request arrives with a `10.10.0.x` source IP that the allowlist accepts.

### c) Up / down

```bash
sudo wg-quick up wg0       # alias on the laptop: spacevpn
sudo wg-quick down wg0     # alias: spacevpn-down
ping -c2 10.10.0.1         # tunnel alive
```

---

## 2. Add a new peer

On polaris2:

```bash
cd /etc/wireguard
umask 077
wg genkey | sudo tee client_<name>_private.key | wg pubkey | sudo tee client_<name>_public.key
# pick the next free 10.10.0.<N>, then append to wg0.conf:
#   [Peer]
#   # <name>
#   PublicKey = <contents of client_<name>_public.key>
#   AllowedIPs = 10.10.0.<N>/32
sudo wg syncconf wg0 <(wg-quick strip wg0)   # apply without dropping existing peers
```

Hand the client its **private** key + the **server public** key (`sudo wg show wg0`) and the
`/etc/hosts` block above. Never reuse a private key across devices.

---

## 3. Gate a new admin service

Prepend the middleware (first in the chain → blocked = clean `403`, no auth-prompt leak):

```yaml
- "traefik.http.routers.<name>.middlewares=internal-only@file,security-headers@file"
```

`internal-only` is defined in `traefik/dynamic/middlewares.yml`. Recreate the container
(`docker compose up -d <name>`). If you add it to the `traefik` container's own dashboard
router, recreating Traefik causes a ~2–5s routing blip on all sites.

If the service is monitored by Uptime Kuma, repoint its monitor to the **internal** endpoint
(`http://<container>:<port>/...`) so it checks real health instead of the proxy's `403`.

---

## 4. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `403` on an admin host | Not on the VPN (or browser DoH bypassing `/etc/hosts` → hits public IP) | Connect the tunnel; disable DoH for these hosts, or rely on the OS resolver |
| Timeout (no response) | `/etc/hosts` points to `10.10.0.1` but the tunnel is down | `sudo wg-quick up wg0` |
| `latest handshake` = `(none)` in `wg show` | Handshake never completed | Check ufw `51820/udp`, client `Endpoint`, and keys |
| Public site (cativo.dev) `403` | Allowlist wrongly attached to a public router | Remove `internal-only@file` from that router's label |
