#!/bin/bash
# backup_ums.sh — Dump umsdb to a timestamped gzipped SQL file.
# Run INSIDE mypostgresql_db-container.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../umsdb/.env"

BACKUP_DIR="/backups/ums"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/umsdb_$TIMESTAMP.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[INFO] Backing up $UMS_DB..."
pg_dump -U "$UMS_USER" -h "$PG_HOST" -p "$PG_PORT" "$UMS_DB" | gzip > "$BACKUP_FILE"
echo "[OK]  Saved to $BACKUP_FILE"
