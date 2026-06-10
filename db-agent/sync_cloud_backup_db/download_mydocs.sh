#!/bin/bash
# download_mydocs.sh — Download mydocs backups from Google Drive to mountspace.
# Run on the HOST.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
LOCAL_DIR="$WORKSPACE_ROOT/mountspace/backups/mydocs"
REMOTE="gdrive:myworkspace-backups/mydocs"

mkdir -p "$LOCAL_DIR"

echo "[INFO] Downloading mydocs backups from $REMOTE..."
rclone copy "$REMOTE" "$LOCAL_DIR" --progress
echo "[OK]  Downloaded to $LOCAL_DIR"
