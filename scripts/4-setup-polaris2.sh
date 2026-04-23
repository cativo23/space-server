#!/bin/bash
# Setup polaris2 with configuration and prepare for migration
# Run on: local machine
# Usage: bash scripts/4-setup-polaris2.sh

set -e

SERVER="polaris2"
BACKUP_DIR="$HOME/backups/space-server-migration"
REMOTE_DIR="space-server"

echo "=== Setup Polaris2 Script ==="
echo ""

# Find latest backup
LATEST_BACKUP=$(ls -td "$BACKUP_DIR"/migration-backup-* 2>/dev/null | grep -v ".tar.gz" | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No backup found"
    echo "Run scripts/2-download-backup.sh first"
    exit 1
fi

echo "Using backup: $LATEST_BACKUP"
echo ""

# 1. Create remote directory
echo "1. Creating remote directory structure..."
ssh "$SERVER" "mkdir -p ~/$REMOTE_DIR"

# 2. Transfer configuration files
echo ""
echo "2. Transferring configuration files..."
scp -r "$LATEST_BACKUP/config/"* "$SERVER:~/$REMOTE_DIR/"

# 3. Transfer acme.json with correct permissions
echo ""
echo "3. Transferring Let's Encrypt certificates..."
if [ -f "$LATEST_BACKUP/state/acme.json" ]; then
    scp "$LATEST_BACKUP/state/acme.json" "$SERVER:~/$REMOTE_DIR/traefik/letsencrypt/"
    ssh "$SERVER" "chmod 600 ~/$REMOTE_DIR/traefik/letsencrypt/acme.json"
    echo "   ✓ acme.json transferred with correct permissions"
fi

# 4. Create Docker network
echo ""
echo "4. Creating Docker networks..."
ssh "$SERVER" "docker network create web 2>/dev/null || echo '   Network web already exists'"

# 5. Transfer volume backups
echo ""
echo "5. Transferring volume backups (this may take a while)..."
ssh "$SERVER" "mkdir -p /tmp/volume-backups"
scp "$LATEST_BACKUP/volumes/"*.tar.gz "$SERVER:/tmp/volume-backups/" 2>/dev/null || echo "   No volumes to transfer"

# 6. Restore volumes (without starting containers)
echo ""
echo "6. Restoring Docker volumes..."
VOLUMES=$(ls "$LATEST_BACKUP/volumes/"*.tar.gz 2>/dev/null | xargs -n1 basename | sed 's/.tar.gz//')

for volume in $VOLUMES; do
    echo "   Restoring $volume..."
    ssh "$SERVER" "docker volume create $volume"
    ssh "$SERVER" "docker run --rm -v $volume:/data -v /tmp/volume-backups:/backup alpine tar xzf /backup/${volume}.tar.gz -C /data"
    echo "   ✓ $volume restored"
done

# 7. Verify setup
echo ""
echo "7. Verifying setup..."
ssh "$SERVER" "ls -la ~/$REMOTE_DIR/docker-compose.yml" && echo "   ✓ docker-compose.yml present"
ssh "$SERVER" "ls -la ~/$REMOTE_DIR/.env" && echo "   ✓ .env present"
ssh "$SERVER" "docker network inspect web >/dev/null 2>&1" && echo "   ✓ web network exists"

# 8. Show volume status
echo ""
echo "8. Docker volumes on polaris2:"
ssh "$SERVER" "docker volume ls"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Polaris2 is ready for migration!"
echo ""
echo "⚠️  DO NOT START SERVICES YET"
echo ""
echo "Next steps:"
echo "1. Review DNS records and prepare for update"
echo "2. Schedule maintenance window"
echo "3. Run final cutover: bash scripts/5-cutover.sh"
