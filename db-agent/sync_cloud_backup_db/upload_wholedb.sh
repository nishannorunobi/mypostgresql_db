#!/bin/bash
# upload_wholedb.sh — Upload whole-db backups from mountspace to Google Drive.
# Run on the HOST.
set -euo pipefail

# ── Mirror logging ─────────────────────────────────────────────────────────────
_WS_ROOT="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; while [ ! -d "$d/mountspace" ] && [ "$d" != "/" ]; do d="$(dirname "$d")"; done; echo "$d")"
if [ -f "$_WS_ROOT/init/create_logging_path.sh" ]; then
    source "$_WS_ROOT/init/create_logging_path.sh"
    setup_logging
fi
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
LOCAL_DIR="$WORKSPACE_ROOT/mountspace/backups/wholedb"
REMOTE="gdrive:myworkspace-backups/wholedb"

if [ ! -d "$LOCAL_DIR" ] || [ -z "$(ls -A "$LOCAL_DIR" 2>/dev/null)" ]; then
    echo "[ERROR] No backups found at $LOCAL_DIR — run backup_db/backup_wholedb.sh first."
    exit 1
fi

echo "[INFO] Uploading whole-db backups to $REMOTE..."
rclone copy "$LOCAL_DIR" "$REMOTE" --progress
echo "[OK]  Upload complete."
