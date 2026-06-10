#!/bin/bash
# backup_wholedb.sh — Dump all databases and roles using pg_dumpall.
# Run INSIDE mypostgresql_db-container.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../umsdb/.env"

BACKUP_DIR="/backups/wholedb"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/wholedb_$TIMESTAMP.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[INFO] Backing up all databases..."
pg_dumpall -U "$PG_SUPERUSER" -h "$PG_HOST" -p "$PG_PORT" | gzip > "$BACKUP_FILE"
echo "[OK]  Saved to $BACKUP_FILE"
