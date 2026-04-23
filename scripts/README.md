# Migration Scripts: cativo.dev → polaris2

Automated scripts for migrating the entire space-server infrastructure from cativo.dev (3.4GB RAM) to polaris2 (7.6GB RAM).

## Quick Start

```bash
# 1. Backup old server
ssh cativo.dev 'bash -s' < scripts/1-backup-cativo.sh

# 2. Download backup locally
bash scripts/2-download-backup.sh

# 3. Verify backup integrity
bash scripts/3-verify-backup.sh

# 4. Setup new server
bash scripts/4-setup-polaris2.sh

# 5. Execute cutover (DOWNTIME)
bash scripts/5-cutover.sh

# 6. Verify migration (after DNS update)
bash scripts/6-verify-migration.sh
```

## Scripts Overview

### 1-backup-cativo.sh
**Run on:** cativo.dev (via SSH)  
**Purpose:** Creates complete backup of configuration, volumes, and state

**What it backs up:**
- Let's Encrypt certificates (acme.json)
- Docker volumes (Ghost, Grafana, Mail, etc.)
- Configuration files (docker-compose.yml, .env, traefik/, mail-server/)
- Container and network state

**Output:** `/tmp/migration-backup-YYYYMMDD-HHMMSS.tar.gz`

### 2-download-backup.sh
**Run on:** Local machine  
**Purpose:** Downloads and extracts backup from cativo.dev

**Output:** `~/backups/space-server-migration/migration-backup-*/`

### 3-verify-backup.sh
**Run on:** Local machine  
**Purpose:** Validates backup integrity before migration

**Checks:**
- Critical files present (acme.json, docker-compose.yml, .env)
- Volume archives are valid
- Permissions are correct
- Required environment variables exist

### 4-setup-polaris2.sh
**Run on:** Local machine  
**Purpose:** Prepares polaris2 with configuration and data

**Actions:**
- Transfers configuration files
- Restores Let's Encrypt certificates
- Creates Docker networks
- Restores Docker volumes
- Does NOT start services yet

### 5-cutover.sh
**Run on:** Local machine  
**Purpose:** Executes the actual migration (causes downtime)

**Steps:**
1. Stops all services on cativo.dev
2. Final incremental backup
3. Restores final changes to polaris2
4. Starts all services on polaris2
5. Provides DNS update instructions

**Estimated downtime:** 10-20 minutes

### 6-verify-migration.sh
**Run on:** Local machine (after DNS propagation)  
**Purpose:** Verifies migration was successful

**Checks:**
- DNS propagation
- SSL certificates
- Mail server ports
- Container status
- Service endpoints
- Logs for errors

## Prerequisites

- SSH access to both servers configured in `~/.ssh/config`
- Docker installed on polaris2 (done by setup-polaris2.sh)
- Sufficient disk space locally for backups (~5-10GB)
- DNS access to update A records

## Migration Timeline

### 24 hours before
- Set DNS TTL to 300 seconds (5 minutes)
- Announce maintenance window

### Day of migration
1. **T-30min:** Run backup script (1-backup-cativo.sh)
2. **T-20min:** Download and verify backup (2, 3)
3. **T-10min:** Setup polaris2 (4-setup-polaris2.sh)
4. **T-0:** Execute cutover (5-cutover.sh) - **DOWNTIME STARTS**
5. **T+5min:** Update DNS records
6. **T+15min:** Verify migration (6-verify-migration.sh)

### After migration
- Monitor logs for 24-48 hours
- Keep cativo.dev running for 1 week as backup
- Update documentation and monitoring

## Rollback Plan

If issues occur within 30 minutes:

1. Revert DNS to old IP: `186.32.90.71`
2. Start services on cativo.dev:
   ```bash
   ssh cativo.dev "cd ~/space-server && docker compose up -d"
   ssh cativo.dev "cd ~/space-server/mail-server && docker compose up -d"
   ```
3. Investigate issues on polaris2
4. Retry migration after fixes

## DNS Records to Update

All records should point to: `167.235.52.161`

```
cativo.dev              A    167.235.52.161
*.cativo.dev            A    167.235.52.161
mail.cativo.dev         A    167.235.52.161
traefik.cativo.dev      A    167.235.52.161
grafana.cativo.dev      A    167.235.52.161
prometheus.cativo.dev   A    167.235.52.161
```

## Troubleshooting

### Backup fails
- Check disk space on cativo.dev: `df -h`
- Check Docker volumes exist: `docker volume ls`

### Download fails
- Check network connectivity
- Verify SSH access: `ssh cativo.dev "echo OK"`

### Services don't start on polaris2
- Check logs: `ssh polaris2 "docker logs traefik"`
- Verify volumes restored: `ssh polaris2 "docker volume ls"`
- Check .env file: `ssh polaris2 "cat ~/space-server/.env"`

### SSL certificates not working
- Check acme.json permissions: `ssh polaris2 "ls -la ~/space-server/traefik/letsencrypt/acme.json"`
- Should be 600 (rw-------)
- Restart Traefik: `ssh polaris2 "docker restart traefik"`

### Mail server not working
- Check ports are open: `ssh polaris2 "sudo ufw status"`
- Verify mail container: `ssh polaris2 "docker logs mail"`
- Test SMTP: `telnet mail.cativo.dev 25`

## Post-Migration Checklist

- [ ] All services responding (6-verify-migration.sh)
- [ ] SSL certificates valid
- [ ] Mail sending/receiving works
- [ ] Ghost admin accessible
- [ ] Grafana dashboards loading
- [ ] Prometheus collecting metrics
- [ ] No errors in logs
- [ ] Update backup scripts for new server
- [ ] Update monitoring alerts
- [ ] Document any issues encountered

## Files Structure

```
scripts/
├── README.md                    # This file
├── 1-backup-cativo.sh          # Backup old server
├── 2-download-backup.sh        # Download to local
├── 3-verify-backup.sh          # Verify integrity
├── 4-setup-polaris2.sh         # Setup new server
├── 5-cutover.sh                # Execute migration
├── 6-verify-migration.sh       # Verify success
├── setup-polaris2.sh           # Initial server setup (Docker, swap, UFW)
└── increase-swap.sh            # Utility to increase swap
```

## Support

For issues or questions:
1. Check logs: `ssh polaris2 "docker logs <container>"`
2. Review MIGRATION.md for detailed plan
3. Check container status: `ssh polaris2 "docker ps -a"`
