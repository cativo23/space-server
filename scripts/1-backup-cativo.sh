#!/bin/bash
# Backup script for cativo.dev before migration
# Run on: cativo.dev
# Usage: ssh cativo.dev 'bash -s' < scripts/1-backup-cativo.sh

set -e

BACKUP_DIR="/tmp/migration-backup-$(date +%Y%m%d-%H%M%S)"
SPACE_DIR="$HOME/space-server"

echo "=== Migration Backup Script ==="
echo "Backup directory: $BACKUP_DIR"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"/{volumes,config,state}

# 1. Backup Let's Encrypt certificates
echo "1. Backing up Let's Encrypt certificates..."
if [ -f "$SPACE_DIR/traefik/letsencrypt/acme.json" ]; then
    cp -p "$SPACE_DIR/traefik/letsencrypt/acme.json" "$BACKUP_DIR/state/"
    echo "   ✓ acme.json backed up"
else
    echo "   ⚠ acme.json not found"
fi

# 2. Backup configuration files
echo ""
echo "2. Backing up configuration files..."
cd "$SPACE_DIR"

# Main config
cp docker-compose.yml "$BACKUP_DIR/config/" 2>/dev/null || echo "   ⚠ docker-compose.yml not found"
cp .env "$BACKUP_DIR/config/" 2>/dev/null || echo "   ⚠ .env not found"
cp .gitignore "$BACKUP_DIR/config/" 2>/dev/null || true

# Traefik config
mkdir -p "$BACKUP_DIR/config/traefik"
cp -r traefik/* "$BACKUP_DIR/config/traefik/" 2>/dev/null || echo "   ⚠ traefik config not found"

# Mail server config
mkdir -p "$BACKUP_DIR/config/mail-server"
cp -r mail-server/* "$BACKUP_DIR/config/mail-server/" 2>/dev/null || echo "   ⚠ mail-server config not found"

# Other services
cp -r dozzle "$BACKUP_DIR/config/" 2>/dev/null || true
cp -r prometheus "$BACKUP_DIR/config/" 2>/dev/null || true

echo "   ✓ Configuration files backed up"

# 3. Export Docker volumes
echo ""
echo "3. Exporting Docker volumes (this may take a while)..."

# List of volumes to backup
VOLUMES=(
    "ghost-blog-prod_db-data"
    "ghost-blog-prod_ghost-content"
    "grafana-data"
    "prometheus-data"
    "mail-data"
    "mail-state"
    "mail-logs"
    "portfolio-api-deploy_mysql-data"
    "portfolio-api-deploy_redis-data"
    "cliproxyapi_postgres-data"
    "uptime-kuma-data"
)

for volume in "${VOLUMES[@]}"; do
    if docker volume inspect "$volume" &>/dev/null; then
        echo "   Backing up $volume..."
        docker run --rm \
            -v "$volume:/data:ro" \
            -v "$BACKUP_DIR/volumes:/backup" \
            alpine tar czf "/backup/${volume}.tar.gz" -C /data .
        echo "   ✓ $volume backed up"
    else
        echo "   ⚠ $volume not found, skipping"
    fi
done

# 4. Save container list and status
echo ""
echo "4. Saving container information..."
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" > "$BACKUP_DIR/state/containers.txt"
docker volume ls > "$BACKUP_DIR/state/volumes.txt"
docker network ls > "$BACKUP_DIR/state/networks.txt"

# 5. Create backup manifest
echo ""
echo "5. Creating backup manifest..."
cat > "$BACKUP_DIR/MANIFEST.txt" <<EOF
Migration Backup Manifest
========================
Date: $(date)
Hostname: $(hostname)
User: $(whoami)

Configuration Files:
$(ls -lh "$BACKUP_DIR/config/" 2>/dev/null | tail -n +2)

Volume Backups:
$(ls -lh "$BACKUP_DIR/volumes/" 2>/dev/null | tail -n +2)

State Files:
$(ls -lh "$BACKUP_DIR/state/" 2>/dev/null | tail -n +2)

Total Backup Size:
$(du -sh "$BACKUP_DIR" | cut -f1)
EOF

# 6. Create tarball of entire backup
echo ""
echo "6. Creating backup tarball..."
cd /tmp
TARBALL="migration-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar czf "$TARBALL" "$(basename $BACKUP_DIR)"

echo ""
echo "=== Backup Complete ==="
echo "Backup location: /tmp/$TARBALL"
echo "Size: $(du -sh /tmp/$TARBALL | cut -f1)"
echo ""
echo "Next steps:"
echo "1. Download backup: scp cativo.dev:/tmp/$TARBALL ~/backups/"
echo "2. Verify backup integrity"
echo "3. Transfer to polaris2"
