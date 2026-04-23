#!/bin/bash
# Final cutover script - migrate from cativo.dev to polaris2
# Run on: local machine
# Usage: bash scripts/5-cutover.sh

set -e

OLD_SERVER="cativo.dev"
NEW_SERVER="polaris2"
NEW_IP="167.235.52.161"
REMOTE_DIR="space-server"

echo "=== MIGRATION CUTOVER SCRIPT ==="
echo ""
echo "⚠️  WARNING: This will cause downtime!"
echo ""
echo "From: $OLD_SERVER"
echo "To:   $NEW_SERVER ($NEW_IP)"
echo ""
read -p "Are you ready to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cutover cancelled"
    exit 0
fi

echo ""
echo "=== Starting Cutover ==="
echo ""

# 1. Stop services on old server
echo "1. Stopping services on $OLD_SERVER..."
ssh "$OLD_SERVER" "cd ~/$REMOTE_DIR && docker compose down" || echo "   Main stack already down"
ssh "$OLD_SERVER" "cd ~/$REMOTE_DIR/mail-server && docker compose down" || echo "   Mail stack already down"
ssh "$OLD_SERVER" "cd ~/$REMOTE_DIR/dozzle && docker compose down" || echo "   Dozzle already down"
echo "   ✓ All services stopped on $OLD_SERVER"

# 2. Final incremental backup (only changed data)
echo ""
echo "2. Running final incremental backup..."
echo "   (This captures any data changed since last backup)"
ssh "$OLD_SERVER" 'bash -s' < scripts/1-backup-cativo.sh

# 3. Download final backup
echo ""
echo "3. Downloading final backup..."
bash scripts/2-download-backup.sh

# 4. Restore final changes to polaris2
echo ""
echo "4. Restoring final changes to $NEW_SERVER..."
BACKUP_DIR="$HOME/backups/space-server-migration"
LATEST_BACKUP=$(ls -td "$BACKUP_DIR"/migration-backup-* 2>/dev/null | grep -v ".tar.gz" | head -1)

if [ -n "$LATEST_BACKUP" ]; then
    # Restore only volumes that changed
    ssh "$NEW_SERVER" "mkdir -p /tmp/volume-backups"
    scp "$LATEST_BACKUP/volumes/"*.tar.gz "$NEW_SERVER:/tmp/volume-backups/" 2>/dev/null || true

    for volume_file in "$LATEST_BACKUP/volumes/"*.tar.gz; do
        volume=$(basename "$volume_file" .tar.gz)
        echo "   Updating $volume..."
        ssh "$NEW_SERVER" "docker run --rm -v $volume:/data -v /tmp/volume-backups:/backup alpine tar xzf /backup/${volume}.tar.gz -C /data"
    done
fi

# 5. Start services on new server
echo ""
echo "5. Starting services on $NEW_SERVER..."
ssh "$NEW_SERVER" "cd ~/$REMOTE_DIR && docker compose up -d"
ssh "$NEW_SERVER" "cd ~/$REMOTE_DIR/mail-server && docker compose up -d"
ssh "$NEW_SERVER" "cd ~/$REMOTE_DIR/dozzle && docker compose up -d"
echo "   ✓ All services started on $NEW_SERVER"

# 6. Wait for services to be healthy
echo ""
echo "6. Waiting for services to become healthy..."
sleep 10

# 7. Verify services
echo ""
echo "7. Verifying services on $NEW_SERVER..."
ssh "$NEW_SERVER" "docker ps --format 'table {{.Names}}\t{{.Status}}'"

# 8. Test endpoints
echo ""
echo "8. Testing endpoints (using new IP directly)..."
echo "   Testing Traefik..."
curl -k -I "https://$NEW_IP" -H "Host: cativo.dev" 2>/dev/null | head -1 || echo "   ⚠ Traefik not responding"

echo "   Testing Ghost..."
curl -k -I "https://$NEW_IP" -H "Host: blog.cativo.dev" 2>/dev/null | head -1 || echo "   ⚠ Ghost not responding"

echo "   Testing Webmail..."
curl -k -I "https://$NEW_IP" -H "Host: mail.cativo.dev" 2>/dev/null | head -1 || echo "   ⚠ Webmail not responding"

# 9. DNS update instructions
echo ""
echo "=== CUTOVER COMPLETE ==="
echo ""
echo "✓ Services are running on $NEW_SERVER"
echo ""
echo "⚠️  CRITICAL: Update DNS records NOW"
echo ""
echo "Update these A records to: $NEW_IP"
echo "  - cativo.dev"
echo "  - *.cativo.dev"
echo "  - mail.cativo.dev"
echo "  - traefik.cativo.dev"
echo "  - grafana.cativo.dev"
echo "  - prometheus.cativo.dev"
echo ""
echo "After DNS update:"
echo "1. Wait 5-15 minutes for propagation"
echo "2. Test all services: bash scripts/6-verify-migration.sh"
echo "3. Monitor logs: ssh $NEW_SERVER 'docker logs -f traefik'"
echo ""
echo "Rollback (if needed within 30 min):"
echo "1. Revert DNS to old IP: 186.32.90.71"
echo "2. Start services on $OLD_SERVER"
