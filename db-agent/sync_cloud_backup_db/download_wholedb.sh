#!/bin/bash
# download_wholedb.sh — Download whole-db backups from Google Drive to mountspace.
# Run on the HOST.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
LOCAL_DIR="$WORKSPACE_ROOT/mountspace/backups/wholedb"
REMOTE="gdrive:myworkspace-backups/wholedb"

mkdir -p "$LOCAL_DIR"

echo "[INFO] Downloading whole-db backups from $REMOTE..."
rclone copy "$REMOTE" "$LOCAL_DIR" --progress
echo "[OK]  Downloaded to $LOCAL_DIR"
