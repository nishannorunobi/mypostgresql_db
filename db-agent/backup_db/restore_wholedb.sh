#!/bin/bash
# restore_wholedb.sh — Restore all databases from a pg_dumpall backup.
# Run INSIDE mypostgresql_db-container.
# Usage: bash restore_wholedb.sh <backup_file.sql.gz>
set -euo pipefail

BACKUP_FILE="${1:-}"
if [ -z "$BACKUP_FILE" ]; then
    echo "[ERROR] Usage: bash restore_wholedb.sh <backup_file.sql.gz>"
    exit 1
fi
if [ ! -f "$BACKUP_FILE" ]; then
    echo "[ERROR] File not found: $BACKUP_FILE"
    exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../umsdb/.env"

echo "[INFO] Restoring all databases from $BACKUP_FILE..."
gunzip -c "$BACKUP_FILE" | psql -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" postgres
echo "[OK]  Restore complete."
