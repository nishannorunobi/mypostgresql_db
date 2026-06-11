#!/bin/bash
# download_wholedb.sh — Download whole-db backups from Google Drive to mountspace.
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

mkdir -p "$LOCAL_DIR"

echo "[INFO] Downloading whole-db backups from $REMOTE..."
rclone copy "$REMOTE" "$LOCAL_DIR" --progress
echo "[OK]  Downloaded to $LOCAL_DIR"
