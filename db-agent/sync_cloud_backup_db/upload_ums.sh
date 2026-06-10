#!/bin/bash
# upload_ums.sh — Upload ums backups from mountspace to Google Drive.
# Run on the HOST.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
LOCAL_DIR="$WORKSPACE_ROOT/mountspace/backups/ums"
REMOTE="gdrive:myworkspace-backups/ums"

if [ ! -d "$LOCAL_DIR" ] || [ -z "$(ls -A "$LOCAL_DIR" 2>/dev/null)" ]; then
    echo "[ERROR] No backups found at $LOCAL_DIR — run backup_db/backup_ums.sh first."
    exit 1
fi

echo "[INFO] Uploading ums backups to $REMOTE..."
rclone copy "$LOCAL_DIR" "$REMOTE" --progress
echo "[OK]  Upload complete."
