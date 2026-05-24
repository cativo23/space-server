# Runbook: Hetzner Cloud Firewall — polaris2

## Why

Docker publishes container ports directly via `iptables` rules, bypassing `ufw` entirely.
A rule like `ufw deny 143` has no effect on ports published by Docker containers — they are
reachable from the internet regardless. A **Hetzner Cloud Firewall** operates at the
hypervisor/network level, before traffic ever reaches the host OS, so it is immune to this
bypass. This gives us true defense-in-depth on top of the container-level controls.

Background: confirmed in F24 (removed 143/995 host bindings) and F41 (DOCKER-USER chain as
an alternative — lower priority once F40 is adopted).

---

## Firewall rules to apply

Apply these rules to the **polaris2** server in the Hetzner Cloud Console
(Cloud Console → Firewalls → Create Firewall → assign to polaris2).

### Inbound rules (allow)

| Protocol | Port(s)    | Source CIDR   | Purpose                              |
|----------|-----------|---------------|--------------------------------------|
| TCP      | 22        | 0.0.0.0/0, ::/0 | SSH (note: polaris2 uses port 52222 — adjust if you want to lock down the default port too) |
| TCP      | 52222     | 0.0.0.0/0, ::/0 | SSH on non-standard port             |
| TCP      | 80        | 0.0.0.0/0, ::/0 | HTTP (Traefik → redirect to HTTPS)   |
| TCP      | 443       | 0.0.0.0/0, ::/0 | HTTPS (Traefik TLS termination)      |
| TCP      | 25        | 0.0.0.0/0, ::/0 | SMTP (inbound mail)                  |
| TCP      | 465       | 0.0.0.0/0, ::/0 | SMTPS (implicit TLS submission)      |
| TCP      | 587       | 0.0.0.0/0, ::/0 | Submission STARTTLS                  |
| TCP      | 993       | 0.0.0.0/0, ::/0 | IMAPS                                |

> **All other inbound TCP/UDP is implicitly DENIED** — Hetzner Cloud Firewalls default-deny.

### Outbound rules

Leave outbound unrestricted (default Hetzner policy allows all outbound) unless you want to
lock down egress. Restricting egress breaks: Let's Encrypt ACME (80/443 outbound), Resend
SMTP relay (587 outbound), Docker Hub pulls (443 outbound), apt updates.

---

## What this blocks

Ports that Docker previously published to the host but that have no legitimate public need:

| Port  | Formerly exposed by                        | Should be blocked |
|-------|--------------------------------------------|-------------------|
| 9090  | Prometheus (if ever port-mapped)           | Yes — Traefik handles auth |
| 9093  | Alertmanager                               | Yes               |
| 3000  | Grafana (if ever port-mapped)              | Yes               |
| 9100  | node-exporter                              | Yes — internal only |
| 8080  | cAdvisor (if ever port-mapped)             | Yes               |
| Any future accidental publish | any service with port: | Yes |

> Currently none of the monitoring stack ports are published to the host (no `ports:` in their
> compose definitions). The firewall provides a safety net in case that changes accidentally.

---

## How to apply (Hetzner Cloud Console)

1. Log into [console.hetzner.cloud](https://console.hetzner.cloud)
2. Select the **cativo-dev** project (or whichever project polaris2 belongs to)
3. Navigate to **Firewalls** → **Create Firewall**
4. Name it `polaris2-public`
5. Add the inbound rules from the table above
6. Leave outbound as "Allow all outbound"
7. Under **Apply to**, select the `polaris2` server
8. Click **Create Firewall**

## How to apply (Hetzner Cloud API / hcloud CLI)

```bash
# Install hcloud CLI if not already present
# brew install hcloud  OR  apt install hcloud-cli

hcloud firewall create --name polaris2-public

# Add inbound rules
for port in 52222 80 443 25 465 587 993; do
  hcloud firewall add-rule polaris2-public \
    --direction in --protocol tcp --port "$port" \
    --source-ips 0.0.0.0/0 --source-ips ::/0
done

# Assign to polaris2
hcloud firewall apply-to-server polaris2-public --server polaris2
```

---

## Verification after applying

From an external machine (not polaris2):

```bash
# These should CONNECT:
curl -I https://cativo.dev          # 200 / 301
nc -zv <polaris2-ip> 25             # SMTP
nc -zv <polaris2-ip> 587            # Submission
nc -zv <polaris2-ip> 993            # IMAPS

# These should TIME OUT (not refuse — firewall drops):
nc -zv -w 3 <polaris2-ip> 9090     # Prometheus — blocked
nc -zv -w 3 <polaris2-ip> 9100     # node-exporter — blocked
nc -zv -w 3 <polaris2-ip> 8080     # cAdvisor — blocked
```

---

## Related items

- **F24** — removed 143/995 host port bindings from mail-server (Roundcube uses internal Docker network)
- **F41** — `DOCKER-USER` iptables chain (alternative to Hetzner Firewall; lower priority if F40 is adopted)
- **F7** — network segmentation (further reduces blast radius independent of F40)
