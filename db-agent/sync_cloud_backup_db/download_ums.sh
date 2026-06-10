#!/bin/bash
# download_ums.sh — Download ums backups from Google Drive to mountspace.
# Run on the HOST.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
LOCAL_DIR="$WORKSPACE_ROOT/mountspace/backups/ums"
REMOTE="gdrive:myworkspace-backups/ums"

mkdir -p "$LOCAL_DIR"

echo "[INFO] Downloading ums backups from $REMOTE..."
rclone copy "$REMOTE" "$LOCAL_DIR" --progress
echo "[OK]  Downloaded to $LOCAL_DIR"
