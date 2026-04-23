# Migration Plan: cativo.dev → polaris2

**Date:** 2026-04-24  
**From:** cativo.dev (186.32.90.71) - 3.4GB RAM  
**To:** polaris2 (167.235.52.161) - 7.6GB RAM

## Pre-Migration Checklist

- [ ] Verify DNS TTL is set to 300s (5 minutes) 24h before migration
- [ ] Announce maintenance window to users
- [ ] Verify polaris2 has Docker + 8GB swap configured ✅
- [ ] Backup current cativo.dev state

## Services to Migrate

### Core Infrastructure
- **Traefik** - Reverse proxy + Let's Encrypt
- **Docker Socket Proxy** - Security layer
- **Dozzle** - Container logs viewer
- **Uptime Kuma** - Status monitoring

### Monitoring Stack
- **Prometheus** - Metrics collection
- **Grafana** - Dashboards (with persistent data)

### Applications
- **Ghost Blog** - Blog + MySQL database
- **Portfolio** - Main portfolio app
- **Portfolio API** - API + MySQL + Redis
- **Hello Kitty Landing** - Landing page
- **Whoami** - Test service

### Mail Server
- **docker-mailserver** - SMTP/IMAP
- **Roundcube** - Webmail

### Other Services
- **cliproxyapi** - API + Postgres + Docker proxy

## Critical Data to Backup

### 1. Let's Encrypt Certificates
```
traefik/letsencrypt/acme.json (600 permissions)
```

### 2. Docker Volumes
```
ghost-blog-prod_db-data          # Ghost MySQL
ghost-blog-prod_ghost-content    # Ghost content
grafana-data                     # Grafana dashboards
prometheus-data                  # Prometheus metrics
mail-data                        # Mail storage
mail-state                       # Mail state
mail-logs                        # Mail logs
portfolio-api-deploy_mysql-data  # Portfolio MySQL
portfolio-api-deploy_redis-data  # Portfolio Redis
cliproxyapi_postgres-data        # Cliproxy Postgres
uptime-kuma-data                 # Uptime Kuma data
```

### 3. Configuration Files
```
.env                             # Secrets
docker-compose.yml               # Main stack
traefik/                         # Traefik config
mail-server/                     # Mail config
dozzle/                          # Dozzle config
prometheus/                      # Prometheus config
```

## Migration Steps

### Phase 1: Preparation (No Downtime)

1. **Set DNS TTL to 300s** (24h before)
   ```bash
   # Update DNS TTL for cativo.dev to 300 seconds
   # This allows faster DNS propagation during cutover
   ```

2. **Run backup script on cativo.dev**
   ```bash
   ./scripts/backup-for-migration.sh
   ```

3. **Transfer backup to local machine**
   ```bash
   ./scripts/download-backup.sh
   ```

4. **Verify backup integrity**
   ```bash
   ./scripts/verify-backup.sh
   ```

### Phase 2: Setup polaris2 (No Downtime)

1. **Transfer configuration to polaris2**
   ```bash
   ./scripts/setup-polaris2-config.sh
   ```

2. **Create Docker networks**
   ```bash
   ssh polaris2 "docker network create web"
   ```

3. **Restore volumes (without starting services)**
   ```bash
   ./scripts/restore-volumes.sh
   ```

### Phase 3: Cutover (5-10 minutes downtime)

1. **Stop services on cativo.dev**
   ```bash
   ssh cativo.dev "cd ~/space-server && docker compose down"
   ssh cativo.dev "cd ~/space-server/mail-server && docker compose down"
   ssh cativo.dev "cd ~/space-server/dozzle && docker compose down"
   ```

2. **Final incremental backup** (only changed data)
   ```bash
   ./scripts/incremental-backup.sh
   ```

3. **Update DNS A records**
   ```
   cativo.dev           A    167.235.52.161
   *.cativo.dev         A    167.235.52.161
   mail.cativo.dev      A    167.235.52.161
   traefik.cativo.dev   A    167.235.52.161
   grafana.cativo.dev   A    167.235.52.161
   prometheus.cativo.dev A   167.235.52.161
   ```

4. **Start services on polaris2**
   ```bash
   ssh polaris2 "cd ~/space-server && docker compose up -d"
   ssh polaris2 "cd ~/space-server/mail-server && docker compose up -d"
   ssh polaris2 "cd ~/space-server/dozzle && docker compose up -d"
   ```

### Phase 4: Verification

1. **Check all containers are running**
   ```bash
   ssh polaris2 "docker ps"
   ```

2. **Verify SSL certificates**
   ```bash
   curl -I https://cativo.dev
   curl -I https://mail.cativo.dev
   curl -I https://traefik.cativo.dev
   ```

3. **Test mail server**
   ```bash
   # Send test email
   # Check IMAP login
   # Verify SPF/DKIM/DMARC
   ```

4. **Test Ghost blog**
   ```bash
   curl -I https://blog.cativo.dev
   # Login to admin panel
   ```

5. **Verify monitoring**
   ```bash
   # Check Grafana dashboards
   # Verify Prometheus targets
   # Check Uptime Kuma status
   ```

### Phase 5: Cleanup (After 48h of stable operation)

1. **Keep cativo.dev as backup** (1 week)
2. **Monitor logs on polaris2**
3. **Update documentation**
4. **Decommission cativo.dev** (after 1 week)

## Rollback Plan

If issues occur within first 30 minutes:

1. **Revert DNS to old IP** (186.32.90.71)
2. **Start services on cativo.dev**
3. **Investigate issues on polaris2**
4. **Retry migration after fixes**

## Estimated Downtime

- **DNS propagation:** 5-15 minutes (with 300s TTL)
- **Service startup:** 2-3 minutes
- **Total user-facing downtime:** 10-20 minutes

## Post-Migration Tasks

- [ ] Update SSH config to use polaris2 as default
- [ ] Update monitoring alerts with new IP
- [ ] Update firewall rules if needed
- [ ] Document any issues encountered
- [ ] Update backup scripts for new server
