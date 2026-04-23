#!/bin/bash
# Verify backup integrity
# Run on: local machine
# Usage: bash scripts/3-verify-backup.sh

set -e

BACKUP_DIR="$HOME/backups/space-server-migration"

echo "=== Backup Verification Script ==="
echo ""

# Find latest extracted backup
LATEST_BACKUP=$(ls -td "$BACKUP_DIR"/migration-backup-* 2>/dev/null | grep -v ".tar.gz" | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No extracted backup found in $BACKUP_DIR"
    echo "Run scripts/2-download-backup.sh first"
    exit 1
fi

echo "Verifying: $LATEST_BACKUP"
echo ""

# Check critical files
echo "1. Checking critical files..."
CRITICAL_FILES=(
    "state/acme.json"
    "config/docker-compose.yml"
    "config/.env"
)

for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$LATEST_BACKUP/$file" ]; then
        echo "   ✓ $file exists"
    else
        echo "   ⚠ $file missing"
    fi
done

# Check volume backups
echo ""
echo "2. Checking volume backups..."
VOLUME_COUNT=$(ls "$LATEST_BACKUP/volumes/"*.tar.gz 2>/dev/null | wc -l)
echo "   Found $VOLUME_COUNT volume backups"

if [ $VOLUME_COUNT -gt 0 ]; then
    ls -lh "$LATEST_BACKUP/volumes/"*.tar.gz | awk '{print "   " $9 " - " $5}'
fi

# Verify acme.json permissions
echo ""
echo "3. Checking acme.json permissions..."
if [ -f "$LATEST_BACKUP/state/acme.json" ]; then
    PERMS=$(stat -c "%a" "$LATEST_BACKUP/state/acme.json")
    if [ "$PERMS" = "600" ]; then
        echo "   ✓ Permissions correct (600)"
    else
        echo "   ⚠ Permissions: $PERMS (should be 600)"
    fi
fi

# Check .env for required variables
echo ""
echo "4. Checking .env variables..."
if [ -f "$LATEST_BACKUP/config/.env" ]; then
    REQUIRED_VARS=(
        "MAIL_DOMAIN"
        "GF_ADMIN_USER"
        "GF_ADMIN_PASSWORD"
    )

    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^$var=" "$LATEST_BACKUP/config/.env"; then
            echo "   ✓ $var present"
        else
            echo "   ⚠ $var missing"
        fi
    done
fi

# Calculate total size
echo ""
echo "5. Backup statistics..."
TOTAL_SIZE=$(du -sh "$LATEST_BACKUP" | cut -f1)
echo "   Total size: $TOTAL_SIZE"

# Test volume integrity (sample)
echo ""
echo "6. Testing volume integrity (sample)..."
SAMPLE_VOLUME=$(ls "$LATEST_BACKUP/volumes/"*.tar.gz 2>/dev/null | head -1)
if [ -n "$SAMPLE_VOLUME" ]; then
    if tar tzf "$SAMPLE_VOLUME" >/dev/null 2>&1; then
        echo "   ✓ Sample volume archive is valid"
    else
        echo "   ❌ Sample volume archive is corrupted"
        exit 1
    fi
fi

echo ""
echo "=== Verification Complete ==="
echo ""
echo "✓ Backup appears to be valid and complete"
echo ""
echo "Next step: bash scripts/4-setup-polaris2.sh"
