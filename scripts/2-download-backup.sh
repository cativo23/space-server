#!/bin/bash
# Download backup from cativo.dev to local machine
# Run on: local machine
# Usage: bash scripts/2-download-backup.sh

set -e

BACKUP_DIR="$HOME/backups/space-server-migration"
SERVER="cativo.dev"

echo "=== Download Backup Script ==="
echo ""

# Create local backup directory
mkdir -p "$BACKUP_DIR"

# Find the latest backup on server
echo "1. Finding latest backup on $SERVER..."
LATEST_BACKUP=$(ssh "$SERVER" "ls -t /tmp/migration-backup-*.tar.gz 2>/dev/null | head -1")

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No backup found on $SERVER"
    echo "Run scripts/1-backup-cativo.sh first"
    exit 1
fi

echo "   Found: $LATEST_BACKUP"

# Download backup
echo ""
echo "2. Downloading backup..."
scp "$SERVER:$LATEST_BACKUP" "$BACKUP_DIR/"

BACKUP_FILE="$BACKUP_DIR/$(basename $LATEST_BACKUP)"

# Verify download
echo ""
echo "3. Verifying download..."
if [ -f "$BACKUP_FILE" ]; then
    echo "   ✓ Backup downloaded successfully"
    echo "   Location: $BACKUP_FILE"
    echo "   Size: $(du -sh $BACKUP_FILE | cut -f1)"
else
    echo "   ❌ Download failed"
    exit 1
fi

# Extract for verification
echo ""
echo "4. Extracting backup..."
cd "$BACKUP_DIR"
tar xzf "$(basename $LATEST_BACKUP)"

EXTRACTED_DIR=$(basename "$LATEST_BACKUP" .tar.gz)

# Show manifest
echo ""
echo "5. Backup manifest:"
cat "$BACKUP_DIR/$EXTRACTED_DIR/MANIFEST.txt"

echo ""
echo "=== Download Complete ==="
echo "Backup extracted to: $BACKUP_DIR/$EXTRACTED_DIR"
echo ""
echo "Next steps:"
echo "1. Verify backup integrity: bash scripts/3-verify-backup.sh"
echo "2. Transfer to polaris2: bash scripts/4-setup-polaris2.sh"
