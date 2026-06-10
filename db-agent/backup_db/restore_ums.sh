#!/bin/bash
# restore_ums.sh — Restore umsdb from a gzipped SQL backup.
# Run INSIDE mypostgresql_db-container.
# Usage: bash restore_ums.sh <backup_file.sql.gz>
set -euo pipefail

BACKUP_FILE="${1:-}"
if [ -z "$BACKUP_FILE" ]; then
    echo "[ERROR] Usage: bash restore_ums.sh <backup_file.sql.gz>"
    exit 1
fi
if [ ! -f "$BACKUP_FILE" ]; then
    echo "[ERROR] File not found: $BACKUP_FILE"
    exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../umsdb/.env"

echo "[INFO] Restoring $UMS_DB from $BACKUP_FILE..."
gunzip -c "$BACKUP_FILE" | psql -U "$UMS_USER" -h "$PG_HOST" -p "$PG_PORT" "$UMS_DB"
echo "[OK]  Restore complete."
